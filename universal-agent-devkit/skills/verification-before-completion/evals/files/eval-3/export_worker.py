"""Hàng đợi xuất dữ liệu CSV chạy nền."""
import csv
import os


class ExportQueue:
    def __init__(self) -> None:
        self.jobs: dict[str, dict] = {}

    def submit_export(self, job_id: str, rows: list[dict], output_path: str) -> dict:
        self.jobs[job_id] = {
            "status": "queued",
            "rows": list(rows),
            "output_path": output_path,
        }
        return {"job_id": job_id, "http_code": 200, "status": "accepted"}

    def drain(self) -> None:
        for job in self.jobs.values():
            if job["status"] != "queued":
                continue
            rows = job["rows"]
            if rows:
                os.makedirs(os.path.dirname(job["output_path"]) or ".", exist_ok=True)
                fieldnames = list(rows[0].keys())
                with open(job["output_path"], "w", newline="", encoding="utf-8") as fh:
                    writer = csv.DictWriter(fh, fieldnames=fieldnames)
                    writer.writeheader()
                    writer.writerows(rows)
            job["status"] = "completed"
