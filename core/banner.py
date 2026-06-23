from rich.console import Console
from rich.panel import Panel
from rich.text import Text

VERSION = "1.1"

DISCLAIMER_TEXT = """
Use this tool only on devices you own or have explicit written
permission to test.

The developer assumes no responsibility for any illegal or
unethical use.
"""


class Banner:
    def __init__(self):
        self.console = Console()

    def render(self):
        text = Text(DISCLAIMER_TEXT.strip(), style="rgb(255,150,150)")
        panel = Panel(
            text,
            title="[bold red]\u26a0  DISCLAIMER  \u26a0[/bold red]",
            border_style="red",
            padding=(1, 3),
        )
        self.console.print(panel)

    def render_mini(self):
        text = Text()
        text.append("\u25c8 ", style="dim green")
        text.append("AndroXploit", style="bold green")
        text.append(f" v{VERSION} ", style="bold red")
        text.append("\u25c8", style="dim green")
        self.console.print(text)
