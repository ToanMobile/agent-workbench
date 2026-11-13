"""hooks/prompt_context.sh chạy file này thay cho `python3 enrich_context.py --hook` (#1127).

File đưa tên trên dòng lệnh được compile từ nguồn mỗi lần chạy, không qua pyc (Python tutorial, mục 6.1.3 "Compiled Python
files"); đo 13/11: compile enrich_context.py (~1500 dòng) tốn 6,4 ms CPU mỗi prompt ở máy dev, trần hook 110 ms. runpy.run_module chạy đúng module đó với
__name__ == "__main__" (cùng khối lệnh, cùng sys.argv[1:]) nhưng từ pyc. sys.path[0] là thư mục của file này, tức thư mục kit,
như khi chạy enrich_context.py trực tiếp. Không có PYTHONPYCACHEPREFIX thì không ghi __pycache__ vào cây kit (như
enrich_context._no_kit_pycache): kit được link vào repo app."""
import runpy
import sys

if sys.pycache_prefix is None:
    sys.dont_write_bytecode = True
runpy.run_module("enrich_context", run_name="__main__", alter_sys=True)
