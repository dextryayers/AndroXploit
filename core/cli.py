import os
import sys
import shlex
import time
import signal
from pathlib import Path

from prompt_toolkit import PromptSession
from prompt_toolkit.history import FileHistory
from prompt_toolkit.auto_suggest import AutoSuggestFromHistory
from prompt_toolkit.completion import WordCompleter
from prompt_toolkit.key_binding import KeyBindings
from prompt_toolkit.formatted_text import FormattedText
from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.columns import Columns
from rich.text import Text
from rich import box
from rich.layout import Layout
from rich.live import Live
from rich.rule import Rule

from .banner import Banner
from .animator import Animator, LiveProgress, AnimatedStatus
from .module_loader import ModuleLoader
from .session import SessionManager
from .database import Database
from .reporter import ReportGenerator

console = Console()
status = AnimatedStatus()

HISTORY_PATH = os.path.expanduser("~/.androxploit_history")
os.makedirs(os.path.dirname(HISTORY_PATH), exist_ok=True)

HELP_TEXT = """
    [bold green]CORE[/bold green]
      help                           Show this help menu
      banner                         Show the legal disclaimer
      exit / quit                    Exit AndroXploit
      clear                          Clear the terminal

    [bold green]MODULES[/bold green]
      show modules [cat]             List all weapons by category
      show options                   Show active weapon options
      use <module>                   Select a weapon to deploy
      set <opt> <value>              Set a module option
      run / execute                  Deploy the selected weapon
      back                           Deselect current weapon
      info                           Show module details
      search <term>                  Search available modules

    [bold green]SESSION & REPORT[/bold green]
      sessions                       List saved sessions
      sessions -l <id>               Load a saved session
      notes <text>                   Add a note to current session
      report json|html|pdf           Generate a report
      setg <opt> <value>             Set a global option
      show globals                   View global configuration

    [dim]TAB -> auto-complete | Up/Down -> history | Ctrl+C -> cancel[/dim]
"""


class AndroXploitCLI:
    def __init__(self):
        self.banner = Banner()
        self.module_loader = ModuleLoader()
        self.session_manager = SessionManager()
        self.database = Database()
        self.reporter = ReportGenerator(self.session_manager, self.database)
        self.current_module = None
        self.running = True

    def run(self):
        self._startup()
        self._main_loop()

    def _startup(self):
        self.banner.render()
        Rule(style="green")

    def _divider(self):
        console.print(Rule(style="dim green"))

    def _main_loop(self):
        bindings = KeyBindings()

        @bindings.add("c-c")
        def _(event):
            event.app.current_buffer.text = ""
            event.app.current_buffer.validate_and_handle()

        session = PromptSession(
            history=FileHistory(HISTORY_PATH),
            auto_suggest=AutoSuggestFromHistory(),
            key_bindings=bindings,
            complete_while_typing=True,
        )

        while self.running:
            try:
                prompt_display = self._get_prompt()
                cmd = session.prompt(
                    prompt_display,
                    completer=self._get_completer(),
                    style=None,
                )
                self._execute(cmd.strip())
            except KeyboardInterrupt:
                console.print()
                continue
            except EOFError:
                self._cmd_exit([])
                break

    def _get_prompt(self):
        parts = [("fg:green bold", "AndroXploit")]
        if self.current_module:
            parts.append(("fg:red bold", " ["))
            parts.append(("fg:yellow bold", self.current_module.name))
            parts.append(("fg:red bold", "]"))
        parts.append(("fg:green bold", " \u279c "))
        parts.append(("fg:yellow bold", "$ "))
        return FormattedText(parts)

    def _get_completer(self):
        words = [
            "help", "exit", "quit", "banner", "clear",
            "use", "set", "run", "execute", "back", "info", "search",
            "show", "sessions", "notes", "report", "setg",
        ]
        for mod_name in self.module_loader.modules:
            words.append(mod_name)
        return WordCompleter(words, ignore_case=True, sentence=True)

    def _execute(self, cmd_line):
        if not cmd_line:
            return
        try:
            parts = shlex.split(cmd_line)
        except ValueError:
            parts = cmd_line.split()
        command = parts[0].lower()
        args = parts[1:]

        handlers = {
            "help": self._cmd_help,
            "exit": self._cmd_exit,
            "quit": self._cmd_exit,
            "banner": self._cmd_banner,
            "clear": self._cmd_clear,
            "use": self._cmd_use,
            "set": self._cmd_set,
            "run": self._cmd_run,
            "execute": self._cmd_run,
            "back": self._cmd_back,
            "info": self._cmd_info,
            "search": self._cmd_search,
            "show": self._cmd_show,
            "sessions": self._cmd_sessions,
            "notes": self._cmd_notes,
            "report": self._cmd_report,
            "setg": self._cmd_setg,
        }
        handler = handlers.get(command)
        if handler:
            handler(args)
        else:
            console.print(f"  [bold red]\u2718[/bold red] Unknown command: {command}")
            console.print(f"  [dim]Type 'help' for available commands[/dim]")

    def _cmd_help(self, args):
        panel = Panel(
            HELP_TEXT.strip(),
            title="[bold green]\u2699  ANDROXPLOIT COMMANDS  \u2699[/bold green]",
            border_style="green",
            padding=(1, 3),
        )
        console.print(panel)

    def _cmd_exit(self, args):
        self.session_manager.save_session()
        with Animator.premium("[red]Shutting down securely...") as sp:
            time.sleep(0.4)
            sp.text = "[red]Purging session data..."
            time.sleep(0.3)
            sp.ok("[bold green]\u2714  DONE")
        console.print()
        console.print(Panel(
            "[bold red]\u2726  AndroXploit terminated. Stay anonymous.  \u2726[/bold red]",
            border_style="red",
        ))
        self.running = False
        sys.exit(0)

    def _cmd_banner(self, args):
        self.banner.render()
        self._divider()

    def _cmd_clear(self, args):
        os.system("clear" if os.name == "posix" else "cls")

    def _cmd_use(self, args):
        if not args:
            console.print("  [bold red]\u2718[/bold red] Usage: [green]use <module_name>[/green]")
            return
        mod_name = args[0]
        module = self.module_loader.get_module(mod_name)
        if module:
            self.current_module = module
            console.print()
            panel = Panel(
                f"[bold white]{module.description}[/bold white]\n\n"
                + (f"[bold yellow]\u2699  {len(module.options)} option(s) available[/bold yellow]"
                   if hasattr(module, "options") and module.options else "")
                + "\n[dim]set <OPTION> <value>  |  show options  |  run[/dim]",
                title=f"[bold green]\u25c8  {module.name}  \u25c8[/bold green]",
                border_style="green",
                padding=(1, 2),
            )
            console.print(panel)
        else:
            console.print(f"  [bold red]\u2718[/bold red] Module not found: [bold white]{mod_name}[/bold white]")
            suggestions = [m for m in self.module_loader.modules if mod_name.lower() in m.lower()]
            if suggestions:
                console.print(f"  [yellow]Did you mean: {', '.join(suggestions)}?[/yellow]")

    def _cmd_set(self, args):
        if not self.current_module:
            console.print("  [bold red]\u2718[/bold red] No module selected. Use [green]use <module>[/green] first.")
            return
        if len(args) < 2:
            console.print("  [bold red]\u2718[/bold red] Usage: [green]set <OPTION> <value>[/green]")
            return
        opt_name = args[0].upper()
        opt_value = " ".join(args[1:])
        if hasattr(self.current_module, "options") and opt_name in self.current_module.options:
            self.current_module.options[opt_name]["value"] = opt_value
            console.print(f"  [bold green]\u2713[/bold green] [bold white]{opt_name}[/bold white] \u2192 [bold yellow]{opt_value}[/bold yellow]")
        else:
            console.print(f"  [bold red]\u2718[/bold red] Unknown option: [bold white]{opt_name}[/bold white]")
            valid = list(getattr(self.current_module, "options", {}).keys())
            if valid:
                console.print(f"  [dim]Valid: {', '.join(valid)}[/dim]")

    def _cmd_run(self, args):
        if not self.current_module:
            console.print("  [bold red]\u2718[/bold red] No module selected. Use [green]use <module>[/green] first.")
            return
        missing = []
        if hasattr(self.current_module, "options"):
            for opt_name, opt_data in self.current_module.options.items():
                if opt_data.get("required", False) and not opt_data.get("value"):
                    missing.append(opt_name)
        if missing:
            console.print(f"  [bold red]\u2718[/bold red] Required options: [bold yellow]{', '.join(missing)}[/bold yellow]")
            console.print(f"  [dim]Use: set <OPTION> <value>[/dim]")
            return

        start = time.time()
        try:
            console.print(f"\n  [bold green]\u25b6[/bold green] Deploying [bold white]{self.current_module.name}[/bold white] ...")
            console.print(f"  [dim]{'\u2500' * 50}[/dim]")
            result = self.current_module.run()
            elapsed = time.time() - start
            self.session_manager.log_result(self.current_module.name, "success", result)
            console.print(f"\n  [bold green]\u2713[/bold green] Mission complete in [bold]{elapsed:.2f}s[/bold]")
            if result:
                self._display_result(result)
        except Exception as e:
            elapsed = time.time() - start
            self.session_manager.log_result(self.current_module.name, "error", str(e))
            console.print(f"\n  [bold red]\u2718[/bold red] Mission failed after {elapsed:.2f}s")
            console.print(f"  [red]{e}[/red]")

    def _display_result(self, result):
        if isinstance(result, dict):
            for key, value in result.items():
                if isinstance(value, list):
                    if value and isinstance(value[0], dict):
                        table = Table(
                            title=f"[bold green]{key}[/bold green]",
                            border_style="green", header_style="bold yellow",
                            box=box.ROUNDED,
                        )
                        for col in value[0].keys():
                            table.add_column(col.capitalize(), style="white", no_wrap=False)
                        for row in value:
                            rvals = []
                            for k in row.keys():
                                v = str(row.get(k, ""))
                                rvals.append(v[:80] + "..." if len(v) > 80 else v)
                            table.add_row(*rvals)
                        console.print(table)
                    elif value:
                        t = Table(border_style="green", box=box.SIMPLE)
                        t.add_column(key, style="white")
                        for item in value:
                            t.add_row(str(item)[:120])
                        console.print(t)
                elif isinstance(value, dict):
                    t = Table(title=f"[bold green]{key}[/bold green]",
                              border_style="green", header_style="bold yellow",
                              box=box.ROUNDED)
                    t.add_column("Key", style="bold green")
                    t.add_column("Value", style="white")
                    for k, v in value.items():
                        t.add_row(str(k), str(v)[:120])
                    console.print(t)
                elif key not in ("error",) or not value:
                    console.print(f"  [bold white]{key}:[/bold white] [green]{value}[/green]")
        elif isinstance(result, list) and result:
            table = Table(border_style="green", header_style="bold yellow", box=box.ROUNDED)
            if isinstance(result[0], dict):
                for col in result[0].keys():
                    table.add_column(col.capitalize(), style="white")
                for row in result:
                    table.add_row(*[str(row.get(k, ""))[:80] for k in row.keys()])
            else:
                table.add_column("Results", style="white")
                for item in result:
                    table.add_row(str(item))
            console.print(table)
        else:
            console.print(f"  [white]{result}[/white]")

    def _cmd_back(self, args):
        if self.current_module:
            console.print(f"  [bold yellow]\u25c8[/bold yellow] Deselected: [bold white]{self.current_module.name}[/bold white]")
            self.current_module = None
        else:
            console.print("  [bold yellow]\u26a0[/bold yellow] No active module.")

    def _cmd_info(self, args):
        if not self.current_module:
            console.print("  [bold red]\u2718[/bold red] No module selected.")
            return
        mod = self.current_module
        table = Table(title=f"[bold green]\u25c8  {mod.name}  \u25c8[/bold green]",
                      border_style="green", box=box.ROUNDED)
        table.add_column("Property", style="bold yellow")
        table.add_column("Value", style="white")
        table.add_row("Name", mod.name)
        table.add_row("Description", mod.description)
        table.add_row("Author", getattr(mod, "author", "AndroXploit"))
        if hasattr(mod, "options") and mod.options:
            table.add_row("Options", ", ".join(mod.options.keys()))
        console.print(table)

    def _cmd_search(self, args):
        if not args:
            console.print("  [bold red]\u2718[/bold red] Usage: [green]search <term>[/green]")
            return
        term = " ".join(args).lower()
        table = Table(
            title=f"[bold green]Search: '{term}'[/bold green]",
            border_style="green", header_style="bold yellow",
            box=box.ROUNDED,
        )
        table.add_column("Module", style="bold green", no_wrap=True)
        table.add_column("Category", style="blue")
        table.add_column("Description", style="white")
        found = False
        for name, info in sorted(self.module_loader.modules.items()):
            if term in name.lower() or term in info["description"].lower() or term in info["category"].lower():
                table.add_row(name, info["category"], info["description"])
                found = True
        if found:
            console.print(table)
        else:
            console.print(f"  [bold yellow]\u26a0[/bold yellow] No matches for '{term}'")

    def _cmd_show(self, args):
        if not args:
            console.print("  [bold red]\u2718[/bold red] Usage: [green]show <modules|options|globals>[/green]")
            return
        sub = args[0].lower()
        if sub in ("modules", "mods"):
            cat = args[1] if len(args) > 1 else None
            if cat and cat not in self.module_loader.get_categories():
                console.print(f"  [bold red]\u2718[/bold red] Unknown category: [bold white]{cat}[/bold white]")
                console.print(f"  [dim]Categories: {', '.join(self.module_loader.get_categories())}[/dim]")
                return
            self.module_loader.show_modules_table(cat)
        elif sub in ("options", "opts"):
            self._show_options()
        elif sub in ("globals", "global"):
            self._show_globals()
        else:
            console.print(f"  [bold red]\u2718[/bold red] Unknown: [bold white]show {sub}[/bold white]")
            console.print(f"  [dim]Use: modules, options, globals[/dim]")

    def _show_options(self):
        if not self.current_module:
            console.print("  [bold red]\u2718[/bold red] No module selected.")
            return
        mod = self.current_module
        if not hasattr(mod, "options") or not mod.options:
            console.print("  [bold yellow]\u26a0[/bold yellow] No options for this module.")
            return
        table = Table(
            title=f"[bold green]Options: {mod.name}[/bold green]",
            border_style="green", header_style="bold yellow",
            box=box.ROUNDED,
        )
        table.add_column("Option", style="bold green", no_wrap=True)
        table.add_column("Required", style="bold")
        table.add_column("Value", style="white")
        table.add_column("Description", style="dim white")
        for opt_name, opt_data in mod.options.items():
            req = "[red]YES[/red]" if opt_data.get("required") else "[dim]no[/dim]"
            val = str(opt_data.get("value", "")) if opt_data.get("value") else "[dim](unset)[/dim]"
            table.add_row(opt_name, req, val, opt_data.get("description", ""))
        console.print(table)

    def _show_globals(self):
        table = Table(
            title="[bold green]Global Configuration[/bold green]",
            border_style="green", header_style="bold yellow",
            box=box.ROUNDED,
        )
        table.add_column("Option", style="bold green")
        table.add_column("Value", style="white")
        for key, val in self.session_manager.config.items():
            table.add_row(key, str(val))
        console.print(table)

    def _cmd_sessions(self, args):
        if args and args[0] == "-l" and len(args) > 1:
            sid = args[1]
            if self.session_manager.load_session(sid):
                console.print(f"  [bold green]\u2713[/bold green] Loaded session: [bold white]{sid}[/bold white]")
            else:
                console.print(f"  [bold red]\u2718[/bold red] Session not found: [bold white]{sid}[/bold white]")
            return
        sessions = self.session_manager.list_sessions()
        if not sessions:
            console.print("  [bold yellow]\u26a0[/bold yellow] No saved sessions.")
            return
        table = Table(
            title="[bold green]Sessions[/bold green]",
            border_style="green", header_style="bold yellow",
            box=box.ROUNDED,
        )
        table.add_column("ID", style="bold green")
        table.add_column("Started", style="white")
        table.add_column("Modules", style="blue")
        table.add_column("Findings", style="yellow")
        for s in sessions:
            table.add_row(s["id"], s["started"][:19],
                          str(len(s.get("module_history", []))),
                          str(len(s.get("results", []))))
        console.print(table)

    def _cmd_notes(self, args):
        if not args:
            console.print("  [bold red]\u2718[/bold red] Usage: [green]notes <text>[/green]")
            return
        note = " ".join(args)
        self.database.add_note(self.session_manager.current_session["id"], note)
        console.print(f"  [bold green]\u2713[/bold green] Note saved.")

    def _cmd_report(self, args):
        fmt = "html"
        if args:
            fmt = args[0].lower()
        sid = self.session_manager.current_session["id"]
        try:
            with LiveProgress("Generating report...") as lp:
                lp.update(10, "Compiling findings...")
                time.sleep(0.3)
                if fmt == "json":
                    path = self.reporter.generate_json(sid)
                elif fmt == "pdf":
                    path = self.reporter.generate_pdf(sid)
                    lp.update(60, "Rendering PDF layout...")
                    time.sleep(0.4)
                else:
                    path = self.reporter.generate_html(sid)
                lp.update(100, "Finalizing...")
                time.sleep(0.2)
            console.print(f"  [bold green]\u2713[/bold green] Report: [green]{os.path.abspath(path)}[/green]")
        except Exception as e:
            console.print(f"  [bold red]\u2718[/bold red] Report failed: [red]{e}[/red]")

    def _cmd_setg(self, args):
        if len(args) < 2:
            console.print("  [bold red]\u2718[/bold red] Usage: [green]setg <option> <value>[/green]")
            return
        key = args[0].lower()
        value = " ".join(args[1:])
        self.session_manager.set_global(key, value)
        console.print(f"  [bold green]\u2713[/bold green] Global: [bold white]{key}[/bold white] \u2192 [bold yellow]{value}[/bold yellow]")
