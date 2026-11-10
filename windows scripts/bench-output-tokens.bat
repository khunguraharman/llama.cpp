@echo off
setlocal

set "BENCH=build-my-msvc-release\bin\llama-bench.exe"

set "LLAMA_RESULTS=llama-3.2-3B-bench-results.json"
set "LLAMA_MODELS=LLMs\Llama-3.2-3B-Instruct-Q5_K_M.gguf,LLMs\Llama-3.2-3B-Instruct-Q6_K.gguf,LLMs\Llama-3.2-3B-Instruct-Q8_0.gguf"

set "PHI_RESULTS=phi-3.5-mini-bench-results.json"
set "PHI_MODELS=LLMs\Phi-3.5-mini-instruct-Q5_K_M.gguf,LLMs\Phi-3.5-mini-instruct-Q6_K.gguf,LLMs\Phi-3.5-mini-instruct-Q8_0.gguf"

set "QWEN_RESULTS=qwen3-4B-bench-results.json"
set "QWEN_MODELS=LLMs\Qwen3-4B-Q5_K_M.gguf,LLMs\Qwen3-4B-Q6_K.gguf,LLMs\Qwen3-4B-Q8_0.gguf"

set "PROMPT_TOKENS=512"
set "OUTPUT_TOKENS=3277,6554,9830,13107"

if not exist "%BENCH%" (
  echo Could not find "%BENCH%".
  exit /b 1
)

echo Running output-token benchmarks...
echo Fixed prompt tokens: %PROMPT_TOKENS%
echo Output token sweep: %OUTPUT_TOKENS%
echo.

call :RUN_BENCH "%LLAMA_MODELS%" "%LLAMA_RESULTS%"
if errorlevel 1 exit /b %ERRORLEVEL%
call :RUN_BENCH "%PHI_MODELS%" "%PHI_RESULTS%"
if errorlevel 1 exit /b %ERRORLEVEL%
call :RUN_BENCH "%QWEN_MODELS%" "%QWEN_RESULTS%"
if errorlevel 1 exit /b %ERRORLEVEL%

echo All benchmarks complete.
exit /b 0

:RUN_BENCH
set "MODELS=%~1"
set "RESULTS=%~2"

echo Models: %MODELS%
echo Results file: %RESULTS%
echo.

"%BENCH%" ^
  -m "%MODELS%" ^
  -ngl -1 ^
  -sm none ^
  -mg 0 ^
  -r 100 ^
  -p %PROMPT_TOKENS% ^
  -n %OUTPUT_TOKENS% ^
  -o json ^
  --progress > "%RESULTS%"

set "STATUS=%ERRORLEVEL%"
if not "%STATUS%"=="0" (
  echo Benchmark failed with exit code %STATUS%.
  exit /b %STATUS%
)

echo Benchmark complete. Results written to "%RESULTS%".
echo.
exit /b 0
