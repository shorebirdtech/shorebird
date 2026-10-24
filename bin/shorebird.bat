@ECHO OFF
REM cspell:words ERRORLEVEL SETLOCAL usebackq
SETLOCAL
WHERE /Q pwsh.exe && (SET ps=pwsh.exe) || WHERE /Q PowerShell.exe && (SET ps=PowerShell.exe) || (
  ECHO Error: pwsh.exe or PowerShell.exe must be in your PATH. 1>&2
  EXIT /B 1
)
SET "bin=%~dp0"
FOR /F "usebackq delims=" %%v IN ("%bin%internal\flutter.version") DO SET fv=%%v

REM Upgrade rewrites this file: EXIT ends dart's line, CALL reads its code.
SET SHOREBIRD_SETUP_ONLY=1
%ps% -NoProfile -ExecutionPolicy Bypass -File "%bin%shorebird.ps1" || CALL EXIT /B %%ERRORLEVEL%%
SET SHOREBIRD_SETUP_ONLY=
"%bin%cache\flutter\%fv%\bin\cache\dart-sdk\bin\dart.exe" --disable-dart-dev --packages="%bin%..\.dart_tool\package_config.json" "%bin%cache\shorebird.snapshot" %* & CALL EXIT /B %%ERRORLEVEL%%
