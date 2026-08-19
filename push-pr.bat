@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1

REM ---- 1. Ensure git is on PATH (user cmd may have no git) ----
set "PORTABLE_GIT=C:\Users\liufl\.workbuddy\binaries\PortableGit\versions\1.2.0\mingw64\bin"
if exist "%PORTABLE_GIT%\git.exe" set "PATH=%PORTABLE_GIT%;%PATH%"
where git >nul 2>&1
if errorlevel 1 (
    echo [ERROR] git not found. Install Git for Windows: https://git-scm.com/download/win
    pause
    exit /b 1
)

cd /d "%~dp0"

REM ---- 2. Make sure we are on the feature branch ----
git checkout windows-launch-scripts 2>nul

REM ---- 3. Network route: git/GCM must reach github.com, or it hangs forever ----
REM The browser reaches github (via system/proxy), but git's own HTTP stack does not
REM unless a proxy is configured. That is exactly why it "freezes" right after you
REM finish the browser sign-in: GCM gets the auth code locally, then tries to exchange
REM it with GitHub's API over a network git cannot reach -> infinite hang.
REM Setting a proxy fixes BOTH the token exchange and the actual push.

REM First, test direct connectivity; if it works, no proxy is needed.
powershell -NoProfile -Command "try{ $r=Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 https://github.com; if($r.StatusCode -eq 200){exit 0}else{exit 1} }catch{exit 1}" >nul 2>&1
if not errorlevel 1 (
    echo [OK] Direct connection to github.com works; no proxy needed.
    git config --global --unset http.proxy >nul 2>&1
    git config --global --unset https.proxy >nul 2>&1
    goto :PUSH
)

set "PROXY="
if exist "%~dp0proxy.txt" (
    set /p PROXY=<"%~dp0proxy.txt"
)

if not defined PROXY (
    set "PROXYTMP=%TEMP%\sr_proxy.txt"
    if exist "%PROXYTMP%" del /f /q "%PROXYTMP%" >nul 2>&1
    powershell -NoProfile -Command ^
        "$ports=@(7890,7891,8080,8888,8118,10808,10809); $found=''; foreach($p in $ports){ try{ $r=Invoke-WebRequest -UseBasicParsing -Proxy ('http://127.0.0.1:'+$p) -TimeoutSec 2 https://github.com; if($r.StatusCode -eq 200){$found=('http://127.0.0.1:'+$p); break} }catch{} }; if($found -eq ''){ try{ $r=Invoke-WebRequest -UseBasicParsing -Proxy 'socks5://127.0.0.1:1080' -TimeoutSec 2 https://github.com; if($r.StatusCode -eq 200){$found='socks5://127.0.0.1:1080'} }catch{} }; if($found -ne ''){ git config --global http.proxy $found; git config --global https.proxy $found; $found | Out-File -Encoding ascii '%PROXYTMP%' }"
    if exist "%PROXYTMP%" set /p PROXY=<"%PROXYTMP%"
)

if defined PROXY (
    echo [OK] Using proxy: !PROXY!
) else (
    echo [WARN] No local proxy detected. If the push hangs, create a file named
    echo         proxy.txt next to this bat with your proxy URL, e.g.:
    echo             http://127.0.0.1:7890
    echo         Then re-run. Or set it manually:
    echo             git config --global http.proxy http://127.0.0.1:7890
)

:PUSH
REM ---- 4. Push with a hard timeout so it NEVER silently freezes ----
echo === Pushing origin/windows-launch-scripts ===
powershell -NoProfile -Command ^
    "$p=Start-Process git -ArgumentList 'push','--force-with-lease','-u','origin','windows-launch-scripts' -PassThru -NoNewWindow; $ok=$p.WaitForExit(120000); if(-not $ok){Write-Host '[TIMEOUT] push hung 120s - killing it'; $p.Kill(); [Environment]::Exit(2)}; [Environment]::Exit($p.ExitCode)"

if errorlevel 1 (
    echo.
    echo [FAILED] push did not complete.
    echo   1) If a browser login appeared, it may have completed but the network
    echo      route was still blocked. Confirm your proxy (proxy.txt) and re-run.
    echo   2) Or push manually from an interactive shell:
    echo        git push --force-with-lease -u origin windows-launch-scripts
    echo   3) Once the branch is up, open the PR page directly:
    echo        https://github.com/microsoft/skill-recorder/compare/main...AIxingbuxing:windows-launch-scripts
    echo.
    echo Opening an interactive shell so you can finish manually...
    cmd /k
    exit /b 1
)

start "" "https://github.com/microsoft/skill-recorder/compare/main...AIxingbuxing:windows-launch-scripts"
echo.
echo [SUCCESS] Branch pushed. PR creation page opened in your browser.
echo Press any key to close.
pause >nul
