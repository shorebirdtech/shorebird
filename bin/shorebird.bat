REM Borrowed from http://blog.danskingdom.com/allow-others-to-run-your-powershell-scripts-from-a-batch-file-they-will-love-you-for-it/

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

& %powershell_executable% -NoProfile -ExecutionPolicy Bypass -Command "& '%PowerShellScriptPath%' %1% %2% %3% %4%";
