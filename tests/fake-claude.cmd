@echo off
rem Stand-in for claude.exe / codex.exe in tests: CHATQ_CLAUDE points here.
rem What it does is decided by the FAKE_* variables the test sets - see
rem fake-agent.ps1. Nothing in it ever reaches a real model.
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0fake-agent.ps1" %*
