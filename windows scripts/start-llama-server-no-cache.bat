@echo off
setlocal

set "SERVER=%~dp0..\build-my-msvc-release\bin\llama-server.exe"
set "LLAMA_MODEL=%~dp0..\LLMs\Llama-3.2-3B-Instruct-Q8_0.gguf"
set "QWEN_MODEL=%~dp0..\LLMs\Qwen3-4B-Q8_0.gguf"
set "PHI_MODEL=%~dp0..\LLMs\Phi-3.5-mini-instruct-Q8_0.gguf"
set "MODEL=%QWEN_MODEL%"
set "MODEL_ALIAS=qwen"
for %%F in ("%MODEL%") do set "MODEL_NAME=%%~nF"
set "LOG_FILE=%~dp0..\llama-server-%MODEL_NAME%-no-cache.log"

if not exist "%SERVER%" (
  echo Could not find "%SERVER%".
  exit /b 1
)
if not exist "%MODEL%" (
  echo Could not find "%MODEL%".
  exit /b 1
)

echo Starting %MODEL_NAME% on CUDA.
echo Log file: %LOG_FILE%
echo PydanticAI base URL: http://192.168.68.68:8080/v1
echo Model name: %MODEL_ALIAS%
echo API key: use any nonempty placeholder; server authentication is disabled.
echo Keep openai_previous_response_id unset and send full message history.
echo Press Ctrl+C to stop the server.
echo.

"%SERVER%" ^
  -m "%MODEL%" ^
  --alias %MODEL_ALIAS% ^
  --host 192.168.68.68 ^
  --port 8080 ^
  -ngl -1^
  -c 16384 ^
  -b 2048 ^
  -ub 2048 ^
  --parallel 1 ^
  --jinja ^
  --metrics ^
  --perf ^
  --cache-ram 0 ^
  --log-timestamps ^
  --log-colors off ^
  --log-verbosity 4 ^
  --log-file "%LOG_FILE%"


exit /b %ERRORLEVEL%
