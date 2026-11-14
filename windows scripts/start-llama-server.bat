@echo off
setlocal

set "SERVER=%~dp0..\build-my-msvc-release\bin\llama-server.exe"
set "LLAMA_MODEL=%~dp0..\LLMs\Llama-3.2-3B-Instruct-Q8_0.gguf"
set "QWEN_MODEL=%~dp0..\LLMs\Qwen3-4B-Q8_0.gguf"
set "PHI_MODEL=%~dp0..\LLMs\Phi-3.5-mini-instruct-Q8_0.gguf"
set "DEEPSEEK_MODEL=%~dp0..\LLMs\DeepSeek-V4-Pro-Qwen3.5-4B-MTP-Q6_K.gguf"

set "MODEL=%QWEN_MODEL%"
set "MODEL_ALIAS=qwen"
set "MODEL_ARGS="
if "%~1"=="/?" (
  echo Usage: "%~nx0" [qwen^|llama^|phi^|deepseek^|deepseek-no-mtp]
  echo With no option, starts Qwen3-4B-Q8_0.
  echo deepseek enables MTP. deepseek-no-mtp disables MTP.
  exit /b 0
)
if /i "%~1"=="llama" (
  set "MODEL=%LLAMA_MODEL%"
  set "MODEL_ALIAS=llama"
) else if /i "%~1"=="phi" (
  set "MODEL=%PHI_MODEL%"
  set "MODEL_ALIAS=phi"
) else if /i "%~1"=="deepseek" (
  set "MODEL=%DEEPSEEK_MODEL%"
  set "MODEL_ALIAS=deepseek"
  set "MODEL_ARGS=--spec-type draft-mtp --n-predict 3"
) else if /i "%~1"=="deepseek-no-mtp" (
  set "MODEL=%DEEPSEEK_MODEL%"
  set "MODEL_ALIAS=deepseek"
  set "MODEL_ARGS=--spec-type none"
) else if /i not "%~1"=="qwen" if not "%~1"=="" (
  echo Unknown model "%~1". Choose qwen, llama, phi, deepseek, or deepseek-no-mtp.
  exit /b 1
)
for %%F in ("%MODEL%") do set "MODEL_NAME=%%~nF"
set "LOG_FILE=%~dp0..\llama-server-%MODEL_NAME%.log"

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
  --cache-prompt ^
  --cache-ram 12288 ^
  --log-timestamps ^
  --log-colors off ^
  --log-verbosity 4 ^
  --log-file "%LOG_FILE%" %MODEL_ARGS%


exit /b %ERRORLEVEL%
