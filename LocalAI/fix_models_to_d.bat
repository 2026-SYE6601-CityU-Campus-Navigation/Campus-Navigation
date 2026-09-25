@echo off
rem Move Ollama models from C: default location to D:\CityUproject\LocalAI\models
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fix_models_to_d.ps1"
pause
