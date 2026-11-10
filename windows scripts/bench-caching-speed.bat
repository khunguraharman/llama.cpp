@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0"

if not defined CONDA_ENV set "CONDA_ENV=llama.cpp.bench"
if not defined SERVER_EXE set "SERVER_EXE=build-my-msvc-release\bin\llama-server.exe"
if not defined SPEED_BENCH set "SPEED_BENCH=tools\server\bench\speed-bench\speed_bench.py"
if not defined RESULTS_DIR set "RESULTS_DIR=model-speed-bench-results"
set MODEL_VALUES="LLMs\Qwen3-4B-Q8_0.gguf" "LLMs\Phi-3.5-mini-instruct-Q8_0.gguf" "LLMs\Llama-3.2-3B-Instruct-Q8_0.gguf"
if not defined PORT set "PORT=8080"
if not defined BENCH_VALUES set "BENCH_VALUES=throughput_1k"
set "THROUGHPUT_CATEGORY_VALUES=low_entropy"
set "OSL_VALUES=1"
if not defined THROUGHPUT_LIMIT set "THROUGHPUT_LIMIT=300"
if not defined LOG_INTERVAL_MS set "LOG_INTERVAL_MS=100"

if not defined SERVER_ARGS set "SERVER_ARGS=-c 8192 -b 2048 -ub 2048 -ngl -1 -fa on --parallel 1 --jinja --cache-ram 12288"

set "RUN_INDEX=%RESULTS_DIR%\runs.csv"
set "URL=localhost:%PORT%"

for %%M in (%MODEL_VALUES%) do (
  if not exist "%%~M" (
    echo Could not find model "%%~M".
    exit /b 1
  )
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

set "SERVER_PID="
call :FIND_LISTENER
if defined LISTENER_PID (
  echo Port %PORT% is already in use by PID !LISTENER_PID!. Stop that server before running this sweep.
  exit /b 1
)

echo Running model SPEED-Bench sweep...
echo Models: %MODEL_VALUES%
echo Server: %SERVER_EXE%
echo Server args: %SERVER_ARGS%
echo Benches: %BENCH_VALUES%
echo Throughput categories: %THROUGHPUT_CATEGORY_VALUES%
echo OSL values: %OSL_VALUES%
echo Throughput sample limit per category: %THROUGHPUT_LIMIT%
echo GPU memory log interval: %LOG_INTERVAL_MS% ms
echo Process RAM log interval: 1 second
echo Results directory: %RESULTS_DIR%
echo.

if not exist "%RESULTS_DIR%" mkdir "%RESULTS_DIR%"
> "%RUN_INDEX%" echo model,bench,category,osl,concurrency,temperature,json,gpu_csv,ram_csv,server_log

for %%M in (%MODEL_VALUES%) do (
  set "MODEL=%%~M"
  set "MODEL_NAME=%%~nM"
  set "SERVER_TITLE=llama-server-%%~nM-!RANDOM!"
  set "SERVER_LOG=%RESULTS_DIR%\server_%%~nM.log"
  set "SERVER_PID="

  echo Starting llama-server with model "!MODEL!"...
  start "!SERVER_TITLE!" /min "%COMSPEC%" /c title !SERVER_TITLE! ^& "%SERVER_EXE%" -m "!MODEL!" --port %PORT% %SERVER_ARGS% ^> "!SERVER_LOG!" 2^>^&1

  call :WAIT_FOR_SERVER
  if errorlevel 1 goto FAILED

  for %%B in (%BENCH_VALUES%) do (
    for %%C in (%THROUGHPUT_CATEGORY_VALUES%) do (
      for %%O in (%OSL_VALUES%) do (
        set "OUT_JSON=%RESULTS_DIR%\!MODEL_NAME!_%%B_%%C_osl%%O.json"
        echo Running model=!MODEL_NAME! bench=%%B category=%%C osl=%%O...

        call :RUN_WITH_MEMORY "%%B" "%%C" "%%O" "!OUT_JSON!" "%THROUGHPUT_LIMIT%"
        set "STATUS=!ERRORLEVEL!"
        if not "!STATUS!"=="0" goto FAILED

        echo "!MODEL!",%%B,%%C,%%O,1,0,"!OUT_JSON!","!GPU_CSV!","!RAM_CSV!","!SERVER_LOG!" >> "%RUN_INDEX%"
      )
    )
  )

  call :STOP_SERVER
  if errorlevel 1 exit /b !ERRORLEVEL!
  echo Finished model !MODEL_NAME!.
  echo.
)

echo All benchmarks complete.
echo Run index written to "%RUN_INDEX%".
echo JSON outputs written to "%RESULTS_DIR%".
echo Per-run GPU and process RAM CSV files written to "%RESULTS_DIR%".
exit /b 0

:WAIT_FOR_SERVER
for /l %%I in (1,1,60) do (
  call :FIND_LISTENER
  if defined LISTENER_PID (
    set "SERVER_PID=!LISTENER_PID!"
    curl.exe --max-time 2 -fsS "http://%URL%/health" >nul 2>nul
    if not errorlevel 1 (
      echo Server ready with PID !SERVER_PID!.
      exit /b 0
    )
  )
  timeout /t 1 /nobreak >nul
)
echo llama-server did not become healthy. See "!SERVER_LOG!".
exit /b 1

:STOP_SERVER
call :STOP_LOGGER
if not defined SERVER_PID exit /b 0
echo Stopping llama-server PID %SERVER_PID%...
taskkill /pid %SERVER_PID% /t /f >nul 2>nul
for /l %%I in (1,1,10) do (
  call :SERVER_IS_RUNNING
  if errorlevel 1 (
    call :FIND_LISTENER
    if not defined LISTENER_PID (
      set "SERVER_PID="
      exit /b 0
    )
  )
  timeout /t 1 /nobreak >nul
)
echo Could not stop server PID %SERVER_PID% or release port %PORT%. Aborting sweep.
exit /b 1

:FIND_LISTENER
set "LISTENER_PID="
for /f "tokens=2,5" %%A in ('netstat -ano -p tcp ^| findstr /r /c:":%PORT% .*LISTENING"') do set "LISTENER_PID=%%B"
exit /b 0

:SERVER_IS_RUNNING
for /f "tokens=2 delims=," %%P in ('tasklist /fi "PID eq %SERVER_PID%" /fo csv /nh') do (
  if "%%~P"=="%SERVER_PID%" exit /b 0
)
exit /b 1

:RUN_WITH_MEMORY
set "RUN_NAME=%MODEL_NAME%_%~1_%~2_osl%~3"
set "GPU_CSV=%RESULTS_DIR%\%RUN_NAME%.gpu.csv"
set "RAM_CSV=%RESULTS_DIR%\%RUN_NAME%.ram.csv"
set "LOGGER_TITLE=llama-server-gpu-memory-logger-%RUN_NAME%-%RANDOM%"
set "RAM_LOGGER_TITLE=llama-server-ram-memory-logger-%RUN_NAME%-%RANDOM%"
call :FIND_LISTENER
if not "%LISTENER_PID%"=="%SERVER_PID%" (
  echo Server PID %SERVER_PID% is no longer listening on port %PORT%.
  exit /b 1
)
set "RAM_INSTANCE="
for %%F in ("%SERVER_EXE%") do set "RAM_PROCESS_NAME=%%~nF"
for /f "tokens=2 delims=()" %%I in ('typeperf -qx "\Process" ^| findstr /l /c:"(%RAM_PROCESS_NAME%" ^| findstr /e /l /c:"\ID Process"') do call :FIND_RAM_INSTANCE "%%I"
if not defined RAM_INSTANCE (
  echo Could not find private working set counter for PID %SERVER_PID%.
  exit /b 1
)

> "%GPU_CSV%" echo timestamp,index,name,memory_used_mib,memory_free_mib,memory_total_mib,memory_utilization_percent,gpu_utilization_percent
start "!LOGGER_TITLE!" /min "%COMSPEC%" /c title !LOGGER_TITLE! ^& nvidia-smi --query-gpu=timestamp,index,name,memory.used,memory.free,memory.total,utilization.memory,utilization.gpu --format=csv,noheader,nounits -lms %LOG_INTERVAL_MS% ^>^> "%GPU_CSV%"
start "!RAM_LOGGER_TITLE!" /min "%COMSPEC%" /c title !RAM_LOGGER_TITLE! ^& typeperf "\Process(%RAM_INSTANCE%)\ID Process" "\Process(%RAM_INSTANCE%)\Working Set - Private" -si 1 -f CSV -o "%RAM_CSV%" -y

call :RUN_SPEED_BENCH "%~1" "%~2" "%~3" "%~4" "%~5"
set "STATUS=%ERRORLEVEL%"
call :STOP_LOGGER
exit /b %STATUS%

:FIND_RAM_INSTANCE
for /f "tokens=1,2 delims=," %%A in ('typeperf "\Process(%~1)\ID Process" -sc 1') do (
  if "%%~B"=="%SERVER_PID%.000000" set "RAM_INSTANCE=%~1"
)
exit /b 0

:STOP_LOGGER
if defined LOGGER_TITLE taskkill /fi "WINDOWTITLE eq !LOGGER_TITLE!*" /t /f >nul 2>nul
if defined RAM_LOGGER_TITLE taskkill /fi "WINDOWTITLE eq !RAM_LOGGER_TITLE!*" /t /f >nul 2>nul
set "LOGGER_TITLE="
set "RAM_LOGGER_TITLE="
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
echo Last process RAM CSV: "!RAM_CSV!"
echo Server log: "!SERVER_LOG!"
exit /b !STATUS!
