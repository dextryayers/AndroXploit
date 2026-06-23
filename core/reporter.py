import json
import os
from datetime import datetime
from pathlib import Path

from jinja2 import Environment, FileSystemLoader
from fpdf import FPDF

REPORT_TEMPLATE_DIR = Path(__file__).parent.parent / "data" / "templates"


class ReportGenerator:
    def __init__(self, session_manager, database):
        self.session = session_manager
        self.db = database
        os.makedirs("output/reports", exist_ok=True)

    def generate_json(self, session_id=None, output_path=None):
        session_id = session_id or self.session.current_session["id"]
        findings = self.db.get_findings(session_id)
        data = {
            "report_meta": {
                "generated": datetime.now().isoformat(),
                "session_id": session_id,
                "tool": "AndroXploit",
                "version": "1.0.0",
            },
            "findings": findings,
            "summary": self.db.get_summary(session_id),
        }
        path = output_path or f"output/reports/report_{session_id}.json"
        with open(path, "w") as f:
            json.dump(data, f, indent=2)
        return path

    def generate_html(self, session_id=None, output_path=None):
        session_id = session_id or self.session.current_session["id"]
        findings = self.db.get_findings(session_id)
        summary = self.db.get_summary(session_id)

        severity_colors = {
            "critical": "#dc3545",
            "high": "#fd7e14",
            "medium": "#ffc107",
            "low": "#28a745",
            "info": "#17a2b8",
        }

        for f in findings:
            f["severity_color"] = severity_colors.get(f["severity"], "#6c757d")

        html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>AndroXploit Report — {session_id}</title>
<style>
  * {{ margin: 0; padding: 0; box-sizing: border-box; }}
  body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          background: #0d1117; color: #c9d1d9; padding: 20px; }}
  .container {{ max-width: 1200px; margin: 0 auto; }}
  header {{ text-align: center; padding: 30px 0; border-bottom: 1px solid #30363d; margin-bottom: 30px; }}
  h1 {{ color: #58a6ff; font-size: 2em; }}
  .meta {{ color: #8b949e; margin-top: 10px; }}
  .summary {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(120px, 1fr)); gap: 15px; margin-bottom: 30px; }}
  .summary-card {{ background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 20px; text-align: center; }}
  .summary-card .count {{ font-size: 2em; font-weight: bold; }}
  .summary-card .label {{ color: #8b949e; font-size: 0.85em; text-transform: uppercase; }}
  .finding {{ background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 20px; margin-bottom: 15px; }}
  .finding-header {{ display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; }}
  .finding-title {{ font-size: 1.1em; font-weight: 600; }}
  .severity-badge {{ padding: 4px 12px; border-radius: 12px; font-size: 0.8em; font-weight: 600; color: #fff; }}
  .finding-meta {{ color: #8b949e; font-size: 0.85em; margin-bottom: 10px; }}
  .finding-desc {{ line-height: 1.6; }}
  .finding-desc pre {{ background: #0d1117; padding: 10px; border-radius: 6px; overflow-x: auto; margin-top: 10px; }}
  footer {{ text-align: center; color: #8b949e; padding: 30px 0; border-top: 1px solid #30363d; margin-top: 30px; }}
</style>
</head>
<body>
<div class="container">
  <header>
    <h1>⚡ AndroXploit</h1>
    <p class="meta">Android Pentest Framework — Report</p>
    <p class="meta">Session: {session_id} | Generated: {datetime.now().isoformat()}</p>
  </header>
  <div class="summary">
    <div class="summary-card"><div class="count" style="color:#dc3545">{summary["critical"]}</div><div class="label">Critical</div></div>
    <div class="summary-card"><div class="count" style="color:#fd7e14">{summary["high"]}</div><div class="label">High</div></div>
    <div class="summary-card"><div class="count" style="color:#ffc107">{summary["medium"]}</div><div class="label">Medium</div></div>
    <div class="summary-card"><div class="count" style="color:#28a745">{summary["low"]}</div><div class="label">Low</div></div>
    <div class="summary-card"><div class="count" style="color:#58a6ff">{summary["total"]}</div><div class="label">Total</div></div>
  </div>
  <h2 style="margin-bottom:20px;">Findings ({len(findings)})</h2>
"""

        for f in findings:
            html += f"""
  <div class="finding">
    <div class="finding-header">
      <span class="finding-title">{f['title'] or 'Untitled'}</span>
      <span class="severity-badge" style="background:{f['severity_color']}">{f['severity'].upper()}</span>
    </div>
    <div class="finding-meta">
      Module: {f['module_name']} | Type: {f['finding_type'] or 'N/A'} | {f['timestamp']}
    </div>
    <div class="finding-desc">
      {f['description'] or 'No description'}
"""

            if f['data_json']:
                try:
                    data = json.loads(f['data_json'])
                    html += f"<pre>{json.dumps(data, indent=2)}</pre>"
                except json.JSONDecodeError:
                    pass

            html += """
    </div>
  </div>
"""

        html += """
  <footer>
    Generated by <strong>AndroXploit</strong> — Authorized Testing Only
  </footer>
</div>
</body>
</html>"""

        path = output_path or f"output/reports/report_{session_id}.html"
        with open(path, "w") as f:
            f.write(html)
        return path

    def generate_pdf(self, session_id=None, output_path=None):
        session_id = session_id or self.session.current_session["id"]
        findings = self.db.get_findings(session_id)
        summary = self.db.get_summary(session_id)

        pdf = FPDF()
        pdf.add_page()

        pdf.set_font("Helvetica", "B", 24)
        pdf.set_text_color(88, 166, 255)
        pdf.cell(0, 20, "AndroXploit", align="C")
        pdf.ln(15)

        pdf.set_font("Helvetica", "", 12)
        pdf.set_text_color(201, 209, 217)
        pdf.cell(0, 8, f"Android Pentest Framework - Report", align="C")
        pdf.ln(8)
        pdf.cell(0, 8, f"Session: {session_id}", align="C")
        pdf.ln(15)

        pdf.set_text_color(200, 200, 200)
        pdf.set_font("Helvetica", "B", 14)
        pdf.cell(0, 10, "Summary", align="L")
        pdf.ln(12)

        pdf.set_font("Helvetica", "", 11)
        for key in ["critical", "high", "medium", "low", "total"]:
            pdf.cell(0, 8, f"  {key.capitalize()}: {summary[key]}")
            pdf.ln(6)

        pdf.ln(10)
        pdf.set_font("Helvetica", "B", 14)
        pdf.cell(0, 10, f"Findings ({len(findings)})", align="L")
        pdf.ln(12)

        for f in findings:
            pdf.set_font("Helvetica", "B", 11)
            pdf.set_text_color(255, 255, 255)
            pdf.multi_cell(0, 6, f"{f['title'] or 'Untitled'}  [{f['severity'].upper()}]")
            pdf.set_font("Helvetica", "", 9)
            pdf.set_text_color(180, 180, 180)
            pdf.multi_cell(0, 5, f"Module: {f['module_name']} | {f['timestamp']}")
            pdf.set_text_color(200, 200, 200)
            pdf.set_font("Helvetica", "", 10)
            pdf.multi_cell(0, 5, f"{f['description'] or 'No description'}")
            pdf.ln(5)

        path = output_path or f"output/reports/report_{session_id}.pdf"
        pdf.output(path)
        return path
