# -*- coding: utf-8 -*-
"""
本地 Ollama API 调用示例 —— AI 路引模块的本地推理兜底

用法:
    python test_api.py 图书馆        # 生成从地铁站到"图书馆"的步行路引
    python test_api.py              # 默认目的地：图书馆

说明:
    - 服务地址 http://localhost:11434（Ollama 需已安装并运行，见 install_ollama.bat）
    - MODEL 请与 D:\\CityUproject\\LocalAI\\active_model.txt 保持一致
"""
import sys
import json
import urllib.request

MODEL = "qwen3:4b"   # 与 active_model.txt 保持一致，可自行修改


def main():
    dest = sys.argv[1] if len(sys.argv) > 1 else "图书馆"
    prompt = (
        "你是香港城市大学（CityU）的校园导航助手。请为新生生成一段从大学地铁站前往"
        f"{dest}的步行路引。要求：分步骤、写清楚楼层与关键地标、中文输出、150字以内。"
    )
    body = json.dumps({"model": MODEL, "prompt": prompt, "stream": False}).encode("utf-8")
    req = urllib.request.Request(
        "http://localhost:11434/api/generate",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.URLError as e:
        print("无法连接本地 Ollama（http://localhost:11434）。请先运行 install_ollama.bat 部署。")
        print("错误详情:", e)
        sys.exit(1)
    print("模型:", data.get("model"))
    print("-" * 40)
    print(data.get("response", ""))


if __name__ == "__main__":
    main()
