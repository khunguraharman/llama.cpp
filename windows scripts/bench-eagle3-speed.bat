@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0.." || exit /b 1

if not defined CONDA_ENV set "CONDA_ENV=llama.cpp.bench"
if not defined SERVER_EXE set "SERVER_EXE=build-my-msvc-release\bin\llama-server.exe"
if not defined SPEED_BENCH set "SPEED_BENCH=tools\server\bench\speed-bench\speed_bench.py"
if not defined RESULTS_DIR set "RESULTS_DIR=eagle3-speed-bench-results"
if not defined MODEL set "MODEL=LLMs\Qwen3-4B-Q6_K.gguf"
if not defined DRAFT_MODEL set "DRAFT_MODEL=LLMs\Qwen3-4B-eagle3.gguf"
if not defined PORT set "PORT=8080"
if not defined EAGLE3_N_MAX_VALUES set "EAGLE3_N_MAX_VALUES=0 1 2 3 4 5"
if not defined BENCH_VALUES set "BENCH_VALUES=throughput_1k throughput_2k"
if not defined THROUGHPUT_CATEGORY_VALUES set "THROUGHPUT_CATEGORY_VALUES=low_entropy high_entropy"
if not defined OSL_VALUES set "OSL_VALUES=1024 2048 4096"
if not defined THROUGHPUT_LIMIT set "THROUGHPUT_LIMIT=30"
if not defined LOG_INTERVAL_MS set "LOG_INTERVAL_MS=100"

if not defined SERVER_ARGS set "SERVER_ARGS=-c 8192 -b 2048 -ub 2048 -ngl -1 -fa on --parallel 1 --jinja"

set "RUN_INDEX=%RESULTS_DIR%\runs.csv"
set "URL=localhost:%PORT%"

if "%MODEL%"=="" (
  echo Set MODEL near the top of %~nx0 before running.
  echo Example:
  echo   set "MODEL=C:\path\to\model.gguf"
  echo.
  echo Optional environment overrides:
  echo   SERVER_EXE=%SERVER_EXE%
  echo   SERVER_ARGS=%SERVER_ARGS%
  echo   PORT=%PORT%
  echo   RESULTS_DIR=%RESULTS_DIR%
  echo   THROUGHPUT_LIMIT=%THROUGHPUT_LIMIT%
  echo   LOG_INTERVAL_MS=%LOG_INTERVAL_MS%
  exit /b 1
)

if not exist "%MODEL%" (
  echo Could not find model "%MODEL%".
  exit /b 1
)

if not exist "%DRAFT_MODEL%" (
  echo Could not find draft model "%DRAFT_MODEL%".
  exit /b 1
)

if not exist "%SERVER_EXE%" (
  echo Could not find "%SERVER_EXE%".
  exit /b 1
)

if not exist "%SPEED_BENCH%" (
  echo Could not find "%SPEED_BENCH%".
  exit /b 1
)

where nvidia-smi >nul 2>nul
if errorlevel 1 (
  echo Could not find nvidia-smi in PATH.
  exit /b 1
)

echo Running EAGLE3 SPEED-Bench sweep...
echo Model: %MODEL%
echo Draft model: %DRAFT_MODEL%
echo Server: %SERVER_EXE%
echo Server args: %SERVER_ARGS%
echo EAGLE3 n_max values: %EAGLE3_N_MAX_VALUES%
echo Benches: %BENCH_VALUES%
echo Throughput categories: %THROUGHPUT_CATEGORY_VALUES%
echo OSL values: %OSL_VALUES%
echo Throughput sample limit per category: %THROUGHPUT_LIMIT%
echo GPU memory log interval: %LOG_INTERVAL_MS% ms
echo Results directory: %RESULTS_DIR%
echo.

if not exist "%RESULTS_DIR%" mkdir "%RESULTS_DIR%"
echo eagle3_n_max,bench,category,osl,concurrency,temperature,json,gpu_csv,server_log > "%RUN_INDEX%"

for %%N in (%EAGLE3_N_MAX_VALUES%) do (
  set "SPEC_TYPE=draft-eagle3"
  set "DRAFT_ARGS=-md "%DRAFT_MODEL%" --spec-draft-ngl -1"
  if "%%N"=="0" (
    set "SPEC_TYPE=none"
    set "DRAFT_ARGS="
  )
  set "SERVER_TITLE=llama-server-eagle3-n%%N-%RANDOM%"
  set "SERVER_LOG=%RESULTS_DIR%\server_eagle3_n%%N.log"

  echo Starting llama-server with --spec-draft-n-max %%N...
  start "!SERVER_TITLE!" /min "%COMSPEC%" /c title !SERVER_TITLE! ^& "%SERVER_EXE%" -m "%MODEL%" --port %PORT% %SERVER_ARGS% !DRAFT_ARGS! --spec-type !SPEC_TYPE! --spec-draft-n-max %%N ^> "!SERVER_LOG!" 2^>^&1

  call :WAIT_FOR_SERVER
  if errorlevel 1 goto FAILED

  for %%B in (%BENCH_VALUES%) do (
    for %%C in (%THROUGHPUT_CATEGORY_VALUES%) do (
      for %%O in (%OSL_VALUES%) do (
        set "OUT_JSON=%RESULTS_DIR%\eagle3_n%%N_%%B_%%C_osl%%O.json"
        echo Running bench=%%B category=%%C osl=%%O n_max=%%N...

        call :RUN_WITH_MEMORY "%%N" "%%B" "%%C" "%%O" "!OUT_JSON!" "%THROUGHPUT_LIMIT%"
        set "STATUS=!ERRORLEVEL!"
        if not "!STATUS!"=="0" goto FAILED

        echo %%N,%%B,%%C,%%O,1,0,"!OUT_JSON!","!GPU_CSV!","!SERVER_LOG!" >> "%RUN_INDEX%"
      )
    )
  )

  call :STOP_SERVER
  if errorlevel 1 exit /b %ERRORLEVEL%
  echo Finished n_max %%N.
  echo.
)

echo All benchmarks complete.
echo Run index written to "%RUN_INDEX%".
echo JSON outputs written to "%RESULTS_DIR%".
echo Per-run GPU CSV files written to "%RESULTS_DIR%".
exit /b 0

:WAIT_FOR_SERVER
for /l %%I in (1,1,60) do (
  curl.exe -fsS "http://%URL%/health" >nul 2>nul
  if not errorlevel 1 exit /b 0
  timeout /t 1 /nobreak >nul
)
echo llama-server did not become healthy. See "!SERVER_LOG!".
exit /b 1

:STOP_SERVER
call :STOP_LOGGER
if defined SERVER_TITLE (
  taskkill /fi "WINDOWTITLE eq !SERVER_TITLE!*" /t /f >nul 2>nul
)
timeout /t 2 /nobreak >nul
exit /b 0

:RUN_WITH_MEMORY
set "RUN_NAME=eagle3_n%~1_%~2_%~3_osl%~4"
set "GPU_CSV=%RESULTS_DIR%\%RUN_NAME%.gpu.csv"
set "LOGGER_TITLE=llama-server-gpu-memory-logger-%RUN_NAME%-%RANDOM%"

echo timestamp,index,name,memory_used_mib,memory_free_mib,memory_total_mib,memory_utilization_percent,gpu_utilization_percent > "%GPU_CSV%"
start "!LOGGER_TITLE!" /min "%COMSPEC%" /c title !LOGGER_TITLE! ^& nvidia-smi --query-gpu=timestamp,index,name,memory.used,memory.free,memory.total,utilization.memory,utilization.gpu --format=csv,noheader,nounits -lms %LOG_INTERVAL_MS% ^>^> "%GPU_CSV%"

call :RUN_SPEED_BENCH "%~2" "%~3" "%~4" "%~5" "%~6"
set "STATUS=%ERRORLEVEL%"
call :STOP_LOGGER
exit /b %STATUS%

:STOP_LOGGER
if defined LOGGER_TITLE taskkill /fi "WINDOWTITLE eq !LOGGER_TITLE!*" /t /f >nul 2>nul
exit /b 0

:RUN_SPEED_BENCH
setlocal
set "BENCH=%~1"
set "CATEGORY=%~2"
set "OSL=%~3"
set "OUT_JSON=%~4"
set "RUN_LIMIT=%~5"
set "RUN_LIMIT_ARG="
if defined RUN_LIMIT set "RUN_LIMIT_ARG=--limit %RUN_LIMIT%"

call conda activate "%CONDA_ENV%"
if errorlevel 1 (
  echo Failed to activate conda environment "%CONDA_ENV%".
  endlocal & exit /b 1
)

python "%SPEED_BENCH%" ^
  --url "%URL%" ^
  --bench "%BENCH%" ^
  --category "%CATEGORY%" ^
  --osl %OSL% ^
  --concurrency 1 ^
  %RUN_LIMIT_ARG% ^
  --extra-inputs "{""temperature"":0}" ^
  --output "%OUT_JSON%"

set "STATUS=%ERRORLEVEL%"
endlocal & exit /b %STATUS%

:FAILED
set "STATUS=%ERRORLEVEL%"
call :STOP_SERVER
echo Benchmark failed with exit code !STATUS!.
echo Last output JSON: "!OUT_JSON!"
echo Last GPU memory CSV: "!GPU_CSV!"
echo Server log: "!SERVER_LOG!"
exit /b !STATUS!
