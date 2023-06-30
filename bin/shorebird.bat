@ECHO OFF

REM Detect which PowerShell executable is available on the Host
REM PowerShell version <= 5: PowerShell.exe
REM PowerShell version >= 6: pwsh.exe
WHERE /Q pwsh.exe && (
   SET powershell_executable=pwsh.exe
) || WHERE /Q PowerShell.exe && (
    SET powershell_executable=PowerShell.exe
) || (
    ECHO Error: PowerShell executable not found.                        1>&2
    ECHO        Either pwsh.exe or PowerShell.exe must be in your PATH. 1>&2
    EXIT 1
)

SET CurrentDirectory=%~dp0
SET PowerShellScriptPath=%CurrentDirectory%shorebird.ps1

REM Pass up to nine arguments to the PowerShell script
REM This number is arbitrary and can be increased if needed
%powershell_executable% -NoProfile -ExecutionPolicy Bypass -Command "& '%PowerShellScriptPath%' %1 %2 %3 %4 %5 %6 %7 %8 %9";
