state("Dark Light") {}

startup {
    settings.Add("sm", true, "Start after main menu");
    settings.SetToolTip("sm", "Start the timer after choosing a level in the main menu");

    settings.Add("sr", false, "Start after restart");
    settings.SetToolTip("sr", "Start the timer after pressing the ingame [RESTART] button");

    settings.Add("rm", true, "Reset on exit");
    settings.SetToolTip("rm", "Reset when pressing the ingame [EXIT TO MAIN MENU] button");

    settings.Add("rr", false, "Reset on restart");
    settings.SetToolTip("rr", "Reset when pressing the ingame [RESTART] button");

    vars.doUpdate = false;
}

init {
    // Pointer signatures
    var targets = new Dictionary<string, SigScanTarget>{
        // Static field End.triggered
        {"triggered", new SigScanTarget(13,
            "41 FF D3",               // call r11
            "85 C0",                  // test eax, eax
            "0F 84 ????????",         // je [StateManager:Update + fb]
            "48 B8 ????????????????", // mov rax [ptr]
            "0F B6 00"                // movzx eax, byte ptr [rax]
        )},

        // Static instance of StateManager
        {"stateManager", new SigScanTarget(5,
            "89 48 30",               // mov [rax+30], ecx
            "48 B8 ????????????????", // mov rax [ptr]
            "48 8B 08",               // mov rcx, [rax]
            "33 D2"                   // xor edx, edx
        )}
    };

    // Scan for each target
    var ptrs = new Dictionary<string, IntPtr>();
    foreach (string name in targets.Keys) {
        ptrs.Add(name, IntPtr.Zero);

        // Prepare for retry cycle
        for (int i = 0; i < 5; i++) {
            // Iteratively scan each section of the process's memory
            foreach (MemoryBasicInformation page in game.MemoryPages(true)) {
                SignatureScanner scanner = new SignatureScanner(game, page.BaseAddress, (int)page.RegionSize);
                ptrs[name] = scanner.Scan(targets[name]);

                // Break on ptr found
                if (ptrs[name] != IntPtr.Zero) {
                    break;
                }
            }

            if (ptrs[name] != IntPtr.Zero) { break; } // Double break
            print("[ASL] Signature scan for <"+name+"> failed! Retrying...");
            Thread.Sleep(200);
        }

        // ptr not found
        if (ptrs[name] == IntPtr.Zero) {
            print("[ASL] Signature scan couldn't find all the required pointers. Try restarting Dark Light and launching LiveSplit >.<");
            return;
        }
    }

    // Start watching memory addresses
    IntPtr trigOffset = memory.ReadValue<IntPtr>(ptrs["triggered"]);
    IntPtr smOffset   = memory.ReadValue<IntPtr>(memory.ReadValue<IntPtr>(ptrs["stateManager"]));
    vars.watchers = new MemoryWatcherList {
        new MemoryWatcher<bool>(trigOffset)        { Name = "triggered" },
        new MemoryWatcher<bool>(trigOffset + 0x02) { Name = "menuTriggered" },
        new MemoryWatcher<bool>(trigOffset + 0x04) { Name = "restartTriggered" },
        new MemoryWatcher<bool>(smOffset   + 0xC0) { Name = "isFromMainMenu" }
    };

    // Signal a successful init
    vars.doUpdate = true;
}

update {
    if (!vars.doUpdate) return false;
    vars.watchers.UpdateAll(game);
}

start {
    if (settings["sr"] && vars.watchers["restartTriggered"].Old && !vars.watchers["restartTriggered"].Current
     || settings["sm"] && vars.watchers["isFromMainMenu"].Old   && !vars.watchers["isFromMainMenu"].Current
       ) {
        return true;
    }
}

split {
    if (vars.watchers["triggered"].Current && !vars.watchers["triggered"].Old) {
        return true;
    }
}

reset {
    if (settings["rr"] && vars.watchers["restartTriggered"].Current && !vars.watchers["restartTriggered"].Old
     || settings["rm"] && vars.watchers["menuTriggered"].Current    && !vars.watchers["menuTriggered"].Old
       ) {
        return true;
    }
}

isLoading {
    if (vars.watchers["triggered"].Current && vars.watchers["triggered"].Old) {
        return true;
    } else {
        return false;
    }
}
