#!/usr/bin/env python3
"""Reassert the actual MechOS v9 visual design for stores and settings.

This patch runs after legacy/reference generators. It changes only GUI layout and
wiring; package/install/search backends stay on the existing owners.
"""
from __future__ import annotations

import sys
from pathlib import Path

CREATOR_MARKER = "MECHOS_VISUAL_SURFACES_V9_CREATOR"
STORE_MARKER = "MECHOS_VISUAL_SURFACES_V9_UNIFIED_STORE"


def fail(msg: str) -> None:
    raise SystemExit(f"[MechOS Visual Surfaces v9] {msg}")


def class_bounds(text: str, class_name: str) -> tuple[int, int]:
    start = text.find(f"class {class_name}(")
    if start < 0:
        fail(f"class {class_name} not found")
    next_class = text.find("\nclass ", start + 8)
    return start, len(text) if next_class < 0 else next_class


def replace_method(text: str, class_name: str, method: str, replacement: str) -> str:
    c0, c1 = class_bounds(text, class_name)
    start = text.find(f"    def {method}(", c0, c1)
    if start < 0:
        fail(f"{class_name}.{method} not found")
    end = text.find("\n    def ", start + 8, c1)
    if end < 0:
        end = c1
    return text[:start] + replacement.rstrip() + "\n" + text[end:]


CREATOR_STORE = r'''    def app_store(self):
        # MECHOS_VISUAL_SURFACES_V9_CREATOR_STORE
        s,v=self.scroll()

        hero=self.panel(); hero.setObjectName('storeHero'); hl=QHBoxLayout(hero); hl.setContentsMargins(26,20,26,20); hl.setSpacing(18)
        copy=QVBoxLayout(); copy.setSpacing(8)
        eye=QLabel('CREATOR STOREFRONT'); eye.setObjectName('purple'); copy.addWidget(eye)
        title=QLabel('Build your toolchain.'); title.setObjectName('title'); title.setStyleSheet('font-size:36px;font-weight:900'); copy.addWidget(title)
        intro=QLabel('Game engines, 3D tools, streaming apps, Windows compatibility tools and creator bundles — with real installed state and real package backends.'); intro.setObjectName('muted'); intro.setWordWrap(True); copy.addWidget(intro)
        self._mechos_creator_store_search=QLineEdit(); self._mechos_creator_store_search.setPlaceholderText('Search Creator Store…'); copy.addWidget(self._mechos_creator_store_search)
        status=QLabel('POST-INSTALL ONLY  •  REAL PACKAGE STATUS'); status.setObjectName('statusPill'); copy.addWidget(status)
        hl.addLayout(copy,3)
        art=QLabel(); art.setAlignment(Qt.AlignmentFlag.AlignCenter); pix=QPixmap('/usr/share/mechos/branding/reference-hero-v5.svg')
        if not pix.isNull(): art.setPixmap(pix.scaled(500,220,Qt.AspectRatioMode.KeepAspectRatio,Qt.TransformationMode.SmoothTransformation))
        hl.addWidget(art,2); v.addWidget(hero)

        tabs=QHBoxLayout(); tabs.setSpacing(8)
        groups=[
            ('All Apps',None),
            ('Game Engines',['unityhub','unreal','godot']),
            ('3D & Art',['blender','krita']),
            ('Streaming',['obs','kdenlive','audacity','discord']),
            ('Windows Tools',['wine','winetricks','protontricks','bottles','protonupqt']),
        ]
        pages=QStackedWidget(); tab_buttons=[]; store_cards=[]
        def switch(i):
            pages.setCurrentIndex(i)
            for j,b in enumerate(tab_buttons): b.setChecked(i==j)
        for i,(name,ids) in enumerate(groups):
            b=QPushButton(name); b.setObjectName('storeTab'); b.setCheckable(True); b.clicked.connect(lambda _=False,x=i:switch(x)); tab_buttons.append(b); tabs.addWidget(b)
            page=QWidget(); pg=QGridLayout(page); pg.setSpacing(10)
            selected=CATALOG if ids is None else [x for x in CATALOG if x[1] in ids]
            for n,info in enumerate(selected):
                c=AppCard(self,info); c.setMinimumHeight(170); c.setProperty('mechosSearchText',' '.join(str(x) for x in info).lower()); self.cards.append(c); store_cards.append(c); pg.addWidget(c,n//5,n%5)
            pages.addWidget(page)
        v.addLayout(tabs); switch(0); v.addWidget(pages)

        def apply_filter(value):
            needle=str(value).strip().lower()
            for card in store_cards:
                hay=str(card.property('mechosSearchText') or '')
                card.setVisible((not needle) or needle in hay)
        self._mechos_creator_store_search.textChanged.connect(apply_filter)

        lower=QHBoxLayout(); lower.setSpacing(12)
        bundles=self.panel(); bundles.setObjectName('settingsCard'); bl=QVBoxLayout(bundles); bh=QLabel('FEATURED BUNDLES'); bh.setObjectName('section'); bl.addWidget(bh)
        for info in PACKAGES[:3]:
            c=PackageCard(self,info); self.package_cards.append(c); bl.addWidget(c)
        bl.addStretch(); lower.addWidget(bundles,1)

        workflows=self.panel(); workflows.setObjectName('settingsCard'); wl=QVBoxLayout(workflows); wh=QLabel('ONE-CLICK WORKFLOWS'); wh.setObjectName('section'); wl.addWidget(wh)
        for title,preset,detail in [
            ('Indie Game Starter','Game Dev','Unity / Godot • Blender • Git'),
            ('Stream Like a Pro','Streaming','OBS • video • audio'),
            ('3D Artist','3D Artist','Blender • Krita • assets'),
            ('VR World Creator','VRChat Creator','Unity • VRChat workflow'),
        ]:
            b=QPushButton(title+'\n'+detail); b.setObjectName('action'); b.clicked.connect(lambda _=False,p=preset:self.apply_preset(p)); wl.addWidget(b)
        wl.addStretch(); lower.addWidget(workflows,1)

        queue=self.panel(); queue.setObjectName('settingsCard'); ql=QVBoxLayout(queue); qh=QLabel('INSTALL STATUS'); qh.setObjectName('section'); ql.addWidget(qh)
        for appid in ['krita','godot','unreal','obs']:
            info=next((x for x in CATALOG if x[1]==appid),None)
            if not info: continue
            st='Vendor setup' if info[3]=='vendor' else (out([APP,'status',appid]) or 'missing')
            row=QLabel(f'{info[0]}   •   {st}'); row.setWordWrap(True); ql.addWidget(row)
        note=QLabel('Downloads and install progress remain owned by Pacman, Flatpak or the vendor installer.'); note.setObjectName('muted'); note.setWordWrap(True); ql.addWidget(note); ql.addStretch(); lower.addWidget(queue,1)
        v.addLayout(lower); v.addStretch(); return s
'''

CREATOR_SETTINGS = r'''    def settings(self):
        # MECHOS_VISUAL_SURFACES_V9_CREATOR_SETTINGS
        s,v=self.scroll()
        hero=self.panel(); hero.setObjectName('settingsHero'); hl=QHBoxLayout(hero); hl.setContentsMargins(26,20,26,20)
        copy=QVBoxLayout(); eye=QLabel('CREATOR SETTINGS'); eye.setObjectName('purple'); copy.addWidget(eye)
        title=QLabel('Workspace control.'); title.setObjectName('title'); title.setStyleSheet('font-size:34px;font-weight:900'); copy.addWidget(title)
        desc=QLabel('Configure the creator workspace, system, performance, updates and compatibility tools without leaving Creator Mode.'); desc.setObjectName('muted'); desc.setWordWrap(True); copy.addWidget(desc); hl.addLayout(copy,3)
        state=QLabel('CREATOR MODE  •  INSTALLED SYSTEM'); state.setObjectName('statusPill'); hl.addWidget(state,1)
        v.addWidget(hero)

        rows=[
          ('SYSTEM & UPDATES',[
            ('System Settings','Display, input, audio, network and desktop settings',['systemsettings']),
            ('Update Center','MechOS, Arch, drivers and Flatpak updates',['/usr/local/bin/mechos-update-center']),
            ('Recovery Center','Repair, rollback and diagnostic tools',['/usr/local/bin/mechos-recovery-center']),
          ]),
          ('PERFORMANCE & HARDWARE',[
            ('Performance Center','Profiles, monitoring and optimization',['/usr/local/bin/mechos-performance-center']),
            ('Hardware Scan','CPU, GPU, storage and driver diagnostics',['/usr/local/bin/mechos-hardware-scan']),
            ('System Information','About this MechOS installation',['systemsettings','kcm_about-distro']),
          ]),
          ('CREATOR WORKSPACE',[
            ('Creator Folder Setup','Create and repair standard creator folders',['/usr/local/bin/mechos-creator-setup']),
            ('Windows Creator Installer','Install supported Windows-only creator tools',[APP,'windows-installer']),
            ('Creator Store','Return to creator apps, bundles and workflows',None),
          ]),
          ('MODE & SESSION',[
            ('Gaming / MechScope','Return to the gaming command center',['/usr/local/bin/mechos-mode-launch','gaming']),
            ('Desktop Mode','Open the standard Plasma desktop',['/usr/local/bin/mechos-mode-launch','desktop']),
            ('Quick Actions','Open the MechOS side control panel',['/usr/local/bin/mechos-quick-actions']),
          ]),
        ]
        for heading,items in rows:
            self.section(v,heading); row=QHBoxLayout(); row.setSpacing(12)
            for name,detail,cmd in items:
                card=self.panel(); card.setObjectName('settingsCard'); cl=QVBoxLayout(card); cl.setContentsMargins(16,14,16,14)
                t=QLabel(name); t.setStyleSheet('font-size:17px;font-weight:900'); cl.addWidget(t)
                d=QLabel(detail); d.setObjectName('muted'); d.setWordWrap(True); cl.addWidget(d); cl.addStretch()
                b=QPushButton('Open'); b.setObjectName('action')
                if cmd is None: b.clicked.connect(lambda _=False:self.select(4))
                else: b.clicked.connect(lambda _=False,c=cmd:spawn(c))
                cl.addWidget(b); row.addWidget(card,1)
            v.addLayout(row)
        note=QLabel('Settings here launch the real MechOS/KDE tools; this page does not fake device or package state.'); note.setObjectName('muted'); note.setWordWrap(True); v.addWidget(note); v.addStretch(); return s
'''

UNIFIED_STORE = r'''    def build_reference_v5(self):
        # MECHOS_VISUAL_SURFACES_V9_UNIFIED_STORE
        outer=QVBoxLayout(self); outer.setContentsMargins(20,14,20,14); outer.setSpacing(10)
        header=QHBoxLayout(); brand=QLabel('MECHOS'); brand.setObjectName('brand'); header.addWidget(brand); header.addStretch(); title=QLabel('UNIFIED STORE'); title.setObjectName('scope'); header.addWidget(title); header.addStretch(); badge=QLabel('OFFICIAL STORES  •  LOCAL LIBRARY'); badge.setObjectName('statusPill'); header.addWidget(badge); outer.addLayout(header)

        content=QHBoxLayout(); content.setSpacing(12); main=QVBoxLayout(); main.setSpacing(10)
        hero=self.panel('storeHero'); hl=QHBoxLayout(hero); hl.setContentsMargins(28,20,28,20); hl.setSpacing(18)
        copy=QVBoxLayout(); eye=QLabel('ONE LIBRARY'); eye.setObjectName('purple'); copy.addWidget(eye); h=QLabel('Every game. One command center.'); h.setObjectName('title'); copy.addWidget(h)
        copy.addWidget(self.muted('Search supported PC storefronts, launch installed libraries and see real local game state. Purchases, accounts, licenses and downloads stay with each official provider.'))
        self.search=QLineEdit(); self.search.setPlaceholderText('Search games, DLC and addons…'); self.search.returnPressed.connect(self.search_selected); copy.addWidget(self.search)
        actions=QHBoxLayout(); explore=QPushButton('Search Selected Store'); explore.setObjectName('primary'); explore.clicked.connect(self.search_selected); actions.addWidget(explore); manage=QPushButton('Refresh Local Library'); manage.clicked.connect(self.refresh_library); actions.addWidget(manage); copy.addLayout(actions); hl.addLayout(copy,3)
        art=QLabel(); art.setAlignment(Qt.AlignmentFlag.AlignCenter); pix=QPixmap('/usr/share/mechos/branding/reference-hero-v5.svg')
        if not pix.isNull(): art.setPixmap(pix.scaled(520,230,Qt.AspectRatioMode.KeepAspectRatio,Qt.TransformationMode.SmoothTransformation)); hl.addWidget(art,2)
        main.addWidget(hero)

        filters=QHBoxLayout(); filters.setSpacing(8)
        for label in ('Featured','Action','RPG','Shooter','Indie','Linux Ready'):
            b=QPushButton(label); b.setObjectName('storeTab'); b.clicked.connect(lambda _=False,q=label:self.set_query(q)); filters.addWidget(b)
        main.addLayout(filters)

        games_panel=self.panel(); games_panel.setObjectName('settingsCard'); gp=QVBoxLayout(games_panel); gp.setContentsMargins(14,12,14,12)
        sh=QHBoxLayout(); sh.addWidget(self.section('LOCAL / RECENT GAMES')); sh.addStretch(); view=QPushButton('Refresh'); view.clicked.connect(self.refresh_library); sh.addWidget(view); gp.addLayout(sh)
        row=QHBoxLayout(); row.setSpacing(10); shown=self.games[:5]
        if shown:
            for game in shown: row.addWidget(self.game_card(game),1)
        else:
            empty=self.panel('gameCard'); el=QVBoxLayout(empty); et=QLabel('Your local library will appear here'); et.setStyleSheet('font-size:18px;font-weight:900'); el.addWidget(et); el.addWidget(self.muted('Install or sign in to Steam, Heroic or Lutris, then refresh. MechOS does not bundle commercial game art.')); opensteam=QPushButton('Open Steam'); opensteam.clicked.connect(lambda:spawn(['steam','-gamepadui'])); el.addWidget(opensteam); row.addWidget(empty)
        gp.addLayout(row); main.addWidget(games_panel)

        sources=self.panel(); sources.setObjectName('settingsCard'); sl=QVBoxLayout(sources); sl.setContentsMargins(14,10,14,10); sl.addWidget(self.section('STORE SOURCES'))
        sr=QHBoxLayout(); sr.setSpacing(8); self.source_buttons=[]
        for i,(name,_url,cmd) in enumerate(self.STORES):
            p=self.panel('sourceCard'); pl=QVBoxLayout(p); t=QLabel(name.upper()); t.setStyleSheet('font-size:15px;font-weight:900'); pl.addWidget(t)
            ready=self.launcher_ready(cmd); state=QLabel('● Available' if ready else '○ Launcher missing'); state.setStyleSheet('color:#31e981' if ready else 'color:#91a5c1'); pl.addWidget(state)
            b=QPushButton('Use this store'); b.setObjectName('storeTab'); b.setCheckable(True); b.clicked.connect(lambda _=False,x=i:self.select_store(x)); pl.addWidget(b); self.source_buttons.append(b); sr.addWidget(p,1)
        sl.addLayout(sr); main.addWidget(sources); content.addLayout(main,5)

        side=QVBoxLayout(); side.setSpacing(10)
        lib=self.panel(); lib.setObjectName('settingsCard'); ll=QVBoxLayout(lib); ll.addWidget(self.section('LIBRARY & DOWNLOADS')); ll.addWidget(self.info_button('My Library',f'{len(self.games)} Steam game(s) detected',self.refresh_library)); ll.addWidget(self.info_button('Install Queue','Managed by the selected launcher',self.open_selected_launcher)); ll.addWidget(self.info_button('Downloads','Open selected launcher',self.open_selected_launcher)); ll.addWidget(self.info_button('Storage',self.disk_free(),lambda:spawn(['dolphin',str(Path.home())]))); side.addWidget(lib)
        compat=self.panel(); compat.setObjectName('settingsCard'); cl=QVBoxLayout(compat); cl.addWidget(self.section('COMPATIBILITY'))
        for name,desc,color in [('Verified','Tested profile','#31e981'),('Playable','Minor setup','#f3c94e'),('Needs Setup','Profile required','#c77dff'),('Unsupported','Known blocker','#ff5f74'),('Unknown','Not tested','#91a5c1')]:
            line=QLabel(f'●  {name}\n    {desc}'); line.setStyleSheet(f'color:{color};padding:6px'); cl.addWidget(line)
        guide=QPushButton('Open Compatibility Guide'); guide.clicked.connect(lambda:spawn(['xdg-open','https://www.protondb.com/'])); cl.addWidget(guide); side.addWidget(compat); side.addStretch()
        back=QPushButton('Return to MechScope'); back.setObjectName('primary'); back.clicked.connect(self.accept); side.addWidget(back); content.addLayout(side,1); outer.addLayout(content,1)
        footer=QHBoxLayout(); footer.addWidget(QLabel('A  Select     B  Back     Menu     D-Pad / Arrows Navigate')); footer.addStretch(); footer.addWidget(QLabel('Controller-ready')); outer.addLayout(footer); self.select_store(0)
'''


def patch_creator(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if CREATOR_MARKER in text:
        return
    text = replace_method(text, "Creator", "app_store", CREATOR_STORE)
    text = replace_method(text, "Creator", "settings", CREATOR_SETTINGS)
    anchor = text.find("class Creator(")
    text = text[:anchor] + f"# {CREATOR_MARKER}\n" + text[anchor:]
    compile(text, str(path), "exec")
    path.write_text(text, encoding="utf-8")


def patch_store(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if STORE_MARKER in text:
        return
    text = replace_method(text, "UnifiedStore", "build_reference_v5", UNIFIED_STORE)
    anchor = text.find("class UnifiedStore(")
    text = text[:anchor] + f"# {STORE_MARKER}\n" + text[anchor:]
    compile(text, str(path), "exec")
    path.write_text(text, encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[1] not in {"creator", "unified-store"}:
        fail("usage: mechos-visual-surfaces-v9-patch.py {creator|unified-store} <owner.py>")
    path = Path(sys.argv[2])
    if not path.is_file():
        fail(f"owner missing: {path}")
    if sys.argv[1] == "creator":
        patch_creator(path)
    else:
        patch_store(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
