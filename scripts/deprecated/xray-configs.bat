cd /d "%~dp0"

where rg.exe >nul 2>&1 || (
		echo.
    echo [ERROR]: rg.exe was not found in either the system or script folder.
		echo.
		pause
    exit /b 2
)

chcp 65001 >nul

set "URL="

set "type_filter_exclude=type=xhttp|type=grpc|type=raw"
set "country_filter=🇷🇺|🇩🇪|🇫🇮|🇱🇻|🇵🇱|🇸🇪|🇳🇱|🇫🇷"

curl.exe -s %URL% | rg.exe "%country_filter%" | rg.exe -v "%type_filter_exclude%" | clip

#pause