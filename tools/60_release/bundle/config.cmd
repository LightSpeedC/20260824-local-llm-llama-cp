@echo off
rem 配布物の場所の設定（p261002-01）。起動用の cmd と試験スクリプトが読む
rem %~dp0 はこのファイルの置き場所。配布物をどこに置いても、そのまま動く
rem モデルが別の場所にあるときは、LLM_MODEL_DIR だけを書き換える（例: set "LLM_MODEL_DIR=C:\AI-models"）
set "LLM_MODEL_DIR=%~dp0models"
rem エージェントの作業フォルダと空のホーム
set "LLM_WORK_DIR=%~dp0work"
rem 使う llama.cpp。auto は Intel GPU が見えれば Vulkan 版、見えなければ CPU 版
rem 固定するときは llama.cpp-b11320-vulkan / llama.cpp-b11320-cpu / llama.cpp-b11320-cuda
set "LLM_BACKEND=auto"
