import importlib
import inspect
import os
import pkgutil
from pathlib import Path

from rich.console import Console
from rich.table import Table

MODULES_DIR = Path(__file__).parent.parent / "modules"


class ModuleLoader:
    def __init__(self):
        self.console = Console()
        self.modules = {}
        self._discover()

    def _discover(self):
        modules_path = str(MODULES_DIR)
        if modules_path not in [p for p in __import__("sys").path]:
            __import__("sys").path.insert(0, str(MODULES_DIR.parent))

        for importer, modname, ispkg in pkgutil.walk_packages(
            path=[str(MODULES_DIR)], prefix="modules."
        ):
            try:
                spec = importlib.import_module(modname)
                if hasattr(spec, "Module"):
                    module_class = getattr(spec, "Module")
                    if inspect.isclass(module_class):
                        instance = module_class()
                        self.modules[instance.name] = {
                            "instance": instance,
                            "path": modname,
                            "category": modname.split(".")[1] if "." in modname else "general",
                            "description": instance.description,
                        }
            except Exception as e:
                pass

    def get_module(self, name):
        if name in self.modules:
            return self.modules[name]["instance"]
        for key, val in self.modules.items():
            if key == name or key.endswith("/" + name) or key == name.replace("/", "."):
                return val["instance"]
        return None

    def list_modules(self, category=None):
        if category:
            return {k: v for k, v in self.modules.items() if v["category"] == category}
        return self.modules

    def get_categories(self):
        cats = set()
        for mod in self.modules.values():
            cats.add(mod["category"])
        return sorted(cats)

    def show_modules_table(self, category=None):
        table = Table(
            title="[bold green]Available Weapons[/bold green]",
            border_style="green",
            header_style="bold yellow",
            title_style="bold green",
        )
        table.add_column("Module", style="green", no_wrap=True)
        table.add_column("Category", style="blue")
        table.add_column("Description", style="white")

        modules = self.list_modules(category)
        for name, info in sorted(modules.items()):
            table.add_row(name, info["category"], info["description"])

        if table.rows:
            self.console.print(table)
        else:
            self.console.print("[yellow]No modules found.[/yellow]")
