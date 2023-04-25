REM Borrowed from http://blog.danskingdom.com/allow-others-to-run-your-powershell-scripts-from-a-batch-file-they-will-love-you-for-it/

@ECHO OFF
SET CurrentDirectory=%~dp0
SET PowerShellScriptPath=%CurrentDirectory%shorebird.ps1
PowerShell -NoProfile -ExecutionPolicy Bypass -Command "& '%PowerShellScriptPath%' %1% %2% %3% %4%";
