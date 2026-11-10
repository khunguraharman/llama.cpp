@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0.." || exit /b 1

set "BENCH=build-my-msvc-release\bin\llama-bench.exe"

set "RESULTS_DIR=generate-bench-results"
set "RUN_INDEX=%RESULTS_DIR%\runs.csv"
set "MODELS=LLMs\Llama-3.2-3B-Instruct-Q8_0.gguf,LLMs\Phi-3.5-mini-instruct-Q8_0.gguf,LLMs\Qwen3-4B-Q8_0.gguf"
set "REPETITIONS=10"
set "LOG_INTERVAL_MS=100"
set "PROMPT_TOKENS=512"
set "GENERATED_VALUES=512 768 1024 1280 1536 1792 2048 2304 2560 2816 3072 3328 3584 3840 4096"
set "BATCH_VALUES=2048 4096"
set "UBATCH_VALUES=2048 2560 3072 3584 4096"

if not exist "%RESULTS_DIR%" mkdir "%RESULTS_DIR%"
if exist "%RUN_INDEX%" del /q "%RUN_INDEX%" >nul 2>nul

if not exist "%BENCH%" (
  echo Could not find "%BENCH%".
  exit /b 1
)

where nvidia-smi >nul 2>nul
if errorlevel 1 (
  echo Could not find nvidia-smi in PATH.
  exit /b 1
)

echo Running generation benchmarks...
echo Models: %MODELS%
echo Results directory: %RESULTS_DIR%
echo Prompt tokens: %PROMPT_TOKENS%
echo Generated token sweep: %GENERATED_VALUES%
echo Batch sweep: %BATCH_VALUES%
echo UBatch sweep: %UBATCH_VALUES%
echo Skipping combinations where ubatch is greater than batch.
echo.

echo model,prompt_tokens,batch_size,ubatch_size,n_gen,repetitions,bench_json,gpu_csv > "%RUN_INDEX%"

for %%M in (%MODELS:,= %) do (
  for %%N in (%GENERATED_VALUES%) do (
    for %%B in (%BATCH_VALUES%) do (
      for %%U in (%UBATCH_VALUES%) do (
        if %%U LEQ %%B (
          set "MODEL=%%~M"
          set "MODEL_NAME=%%~nM"
          set "RUN_NAME=!MODEL_NAME!_p%PROMPT_TOKENS%_b%%B_ub%%U_n%%N_r%REPETITIONS%"
          set "BENCH_JSON=%RESULTS_DIR%\!RUN_NAME!.json"
          set "GPU_CSV=%RESULTS_DIR%\!RUN_NAME!.gpu.csv"
          set "LOGGER_TITLE=llama-bench-gpu-memory-logger-!RUN_NAME!"

          echo "!MODEL!",%PROMPT_TOKENS%,%%B,%%U,%%N,%REPETITIONS%,"!BENCH_JSON!","!GPU_CSV!" >> "%RUN_INDEX%"
          echo Running !MODEL_NAME! tg %%N with -p %PROMPT_TOKENS% -b %%B -ub %%U...

          echo timestamp,index,name,memory_used_mib,memory_free_mib,memory_total_mib,memory_utilization_percent,gpu_utilization_percent > "!GPU_CSV!"
          start "!LOGGER_TITLE!" /min "%COMSPEC%" /c title !LOGGER_TITLE! ^& nvidia-smi --query-gpu=timestamp,index,name,memory.used,memory.free,memory.total,utilization.memory,utilization.gpu --format=csv,noheader,nounits -lms %LOG_INTERVAL_MS% ^>^> "!GPU_CSV!"

          "%BENCH%" ^
            -m "!MODEL!" ^
            -ngl -1 ^
            -sm none ^
            -mg 0 ^
            -r %REPETITIONS% ^
            -p %PROMPT_TOKENS% ^
            -n %%N ^
            -b %%B ^
            -ub %%U ^
            -o json ^
            --progress > "!BENCH_JSON!"

          set "STATUS=!ERRORLEVEL!"
          call :STOP_LOGGER
          if not "!STATUS!"=="0" goto BENCH_FAILED
        )
      )
    )
  )
)

echo All benchmarks complete.
echo Run index written to "%RUN_INDEX%".
echo Per-run JSON and GPU CSV files written to "%RESULTS_DIR%".
exit /b 0

:BENCH_FAILED
call :STOP_LOGGER

echo Benchmark failed with exit code %STATUS%.
echo Last benchmark JSON: "!BENCH_JSON!"
echo Last GPU memory CSV: "!GPU_CSV!"
exit /b %STATUS%

:STOP_LOGGER
if defined LOGGER_TITLE taskkill /fi "WINDOWTITLE eq !LOGGER_TITLE!*" /t /f >nul 2>nul
exit /b 0
