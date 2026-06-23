from rich.console import Console
from rich.table import Table
from rich.progress import Progress, SpinnerColumn, TextColumn, BarColumn, TimeElapsedColumn

console = Console()


class AndroModule:
    name = ""
    description = ""
    author = "AndroXploit"
    category = ""
    options = {}
    required_options = []

    def __init__(self):
        self.results = {}
        self.console = console

    def get_option(self, name, default=None):
        if name in self.options:
            val = self.options[name].get("value")
            return val if val is not None else default
        return default

    def set_option(self, name, value):
        if name in self.options:
            self.options[name]["value"] = value
            return True
        return False

    def validate_options(self):
        missing = []
        for opt_name, opt_data in self.options.items():
            if opt_data.get("required", False) and not opt_data.get("value"):
                missing.append(opt_name)
        return missing

    def log(self, message, style="white"):
        console.print(f"[dim][{self.name}][/dim] {message}")

    def success(self, message):
        console.print(f"[green][+] {message}[/green]")

    def error(self, message):
        console.print(f"[red][!] {message}[/red]")

    def warn(self, message):
        console.print(f"[yellow][*] {message}[/yellow]")

    def info(self, message):
        console.print(f"[cyan][*] {message}[/cyan]")

    def run(self):
        raise NotImplementedError("Each module must implement a run() method.")

    def progress_bar(self, description="Processing"):
        progress = Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            BarColumn(complete_style="cyan", finished_style="green"),
            TextColumn("[progress.percentage]{task.percentage:>3.0f}%"),
            TimeElapsedColumn(),
            console=console,
        )
        return progress
