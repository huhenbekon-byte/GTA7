"""Бот сервера «СССР РП».

  python bot.py           — запустить бота
  python bot.py --check   — проверить config.py и texts.py без подключения к Discord
  python bot.py --docs    — вывести структуру сервера (Markdown)

На сервере владелец пишет /настроить-сервер — бот создаёт роли, категории,
каналы, права, тексты, кнопки и автомодерацию.
"""
from __future__ import annotations

import asyncio
import datetime as dt
import json
import os
import re
import sys
import time

import discord
from discord import app_commands
from discord.ext import tasks

import config as C
import texts as TX

HERE = os.path.dirname(os.path.abspath(__file__))
DATA_FILE = os.path.join(HERE, "data.json")
VALID = discord.Permissions.VALID_FLAGS


# ═════════════════════════════════ Хранилище ═════════════════════════════════

class Store:
    def __init__(self, path):
        self.path = path
        self.d = {"channels": {}, "messages": {}, "warns": {}, "mutes": {}, "bans": {},
                  "tickets": {}, "ticket_no": 0}
        if os.path.exists(path):
            with open(path, encoding="utf-8") as fh:
                self.d.update(json.load(fh))

    def save(self):
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(self.d, fh, ensure_ascii=False, indent=1)
        os.replace(tmp, self.path)

    def __getitem__(self, k):
        return self.d[k]


store = Store(DATA_FILE)


def load_env():
    path = os.path.join(HERE, ".env")
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"'))


# ═════════════════════════════════ Права ═════════════════════════════════

def perms(**kw):
    return {k: v for k, v in kw.items() if k in VALID}


def channel_rules(cat, ch=None):
    """Кто видит / пишет / управляет / скрыт — с учётом наследования от категории."""
    ch = ch or {}
    view = list(ch.get("view", cat.get("view", [])))
    if "send" in ch:
        send = list(ch["send"])
    elif "send" in cat and "view" not in ch:
        send = list(cat["send"])
    elif "send" in cat:
        # канал переопределил видимость, но не запись: пишут те, кому разрешено в категории
        send = [r for r in cat["send"] if r in view or r == C.EVERYONE]
    else:
        send = list(view)
    manage = list(ch.get("manage", cat.get("manage", [])))
    hidden = list(ch.get("hidden", cat.get("hidden", [])))
    voice = ch.get("type") == "voice"
    return view, send, manage, hidden, voice


def overwrite_spec(cat, ch=None):
    """Возвращает {имя_роли: {право: True/False}} — без привязки к Discord."""
    view, send, manage, hidden, voice = channel_rules(cat, ch)
    out: dict[str, dict] = {}

    def add(role, **kw):
        out.setdefault(role, {}).update(perms(**kw))

    restricted = any(r not in send for r in view)   # кто-то видит, но не пишет
    add(C.EVERYONE, view_channel=C.EVERYONE in view)
    if restricted and C.EVERYONE not in send:
        add(C.EVERYONE, send_messages=False, send_messages_in_threads=False,
            create_public_threads=False, create_private_threads=False,
            **({"speak": False} if voice else {}))
    for r in view:
        if r != C.EVERYONE:
            add(r, view_channel=True, read_message_history=True, **({"connect": True} if voice else {}))
    if restricted:
        for r in send:
            if r != C.EVERYONE:
                add(r, send_messages=True, send_messages_in_threads=True,
                    **({"speak": True} if voice else {}))
    for r in hidden:
        add(r, view_channel=False)
    for r in manage:
        add(r, manage_channels=True, manage_messages=True, pin_messages=True, manage_threads=True,
            **({"mute_members": True, "move_members": True} if voice else {}))
    add(C.BOTS, view_channel=True, send_messages=True, read_message_history=True, embed_links=True)
    add(C.MUTE, send_messages=False, send_messages_in_threads=False, add_reactions=False,
        create_public_threads=False, create_private_threads=False, speak=False)
    return out


def to_overwrites(guild: discord.Guild, spec: dict):
    res = {}
    for name, p in spec.items():
        target = guild.default_role if name == C.EVERYONE else discord.utils.get(guild.roles, name=name)
        if target is not None:
            res[target] = discord.PermissionOverwrite(**p)
    return res


# ═════════════════════════════════ Вспомогательное ═════════════════════════════════

def role(guild, name):
    return discord.utils.get(guild.roles, name=name)


def chan(guild, key) -> discord.abc.GuildChannel | None:
    cid = store["channels"].get(key)
    return guild.get_channel(int(cid)) if cid else None


def staff_level(m: discord.Member) -> int:
    if m.guild.owner_id == m.id:
        return 5
    lvl = 4 if m.guild_permissions.administrator else 0
    for r in m.roles:
        lvl = max(lvl, C.STAFF_LEVEL.get(r.name, 0))
    return lvl


def has_role(m: discord.Member, name: str) -> bool:
    return any(r.name == name for r in m.roles)


def embeds_from(blocks, color=C.RED, **fmt):
    out = []
    for i, (title, text) in enumerate(blocks):
        e = discord.Embed(title=title.format(**fmt) if fmt else title,
                          description=text.format(**fmt) if fmt else text,
                          color=color if i == 0 else C.DARK if i % 2 else C.RED)
        out.append(e)
    out[-1].set_footer(text=C.FOOTER)
    return out


def card(title, desc="", color=C.RED):
    e = discord.Embed(title=title, description=desc, color=color, timestamp=discord.utils.utcnow())
    e.set_footer(text=C.FOOTER)
    return e


async def log(guild, key, embed):
    ch = chan(guild, key)
    if isinstance(ch, discord.TextChannel):
        try:
            await ch.send(embed=embed)
        except discord.HTTPException:
            pass


def fmt_until(ts):
    return f"<t:{int(ts)}:f>" if ts else "навсегда"


# ═════════════════════════════════ Бот ═════════════════════════════════

class Bot(discord.Client):
    def __init__(self, guild_id: int):
        intents = discord.Intents.default()
        intents.members = True
        intents.message_content = True
        super().__init__(intents=intents, allowed_mentions=discord.AllowedMentions(everyone=False, roles=False))
        self.guild_id = guild_id
        self.tree = app_commands.CommandTree(self)
        self.mat = [re.compile(p) for p in C.MAT_PATTERNS]

    async def setup_hook(self):
        self.add_view(VerifyView())
        self.add_view(TicketPanel())
        self.add_view(TicketControl())
        self.add_view(OrgPanel())
        self.add_view(SimpleApplyPanel("admin"))
        self.add_view(SimpleApplyPanel("tester"))
        self.add_dynamic_items(Decision)
        register_commands(self.tree)
        g = discord.Object(id=self.guild_id)
        self.tree.copy_global_to(guild=g)
        await self.tree.sync(guild=g)
        self.timers.start()

    async def on_ready(self):
        print(f"Бот запущен как {self.user}. Серверов: {len(self.guilds)}")

    # ── таймеры мутов и временных банов ──
    @tasks.loop(seconds=30)
    async def timers(self):
        guild = self.get_guild(self.guild_id)
        if not guild:
            return
        now = time.time()
        changed = False
        for uid, until in list(store["mutes"].items()):
            if until and until <= now:
                m = guild.get_member(int(uid))
                r = role(guild, C.MUTE)
                if m and r:
                    try:
                        await m.remove_roles(r, reason="Срок мута истёк")
                    except discord.HTTPException:
                        continue
                del store["mutes"][uid]
                changed = True
                await log(guild, C.CH_PUNISH_LOG, card("🔈 Мут снят", f"<@{uid}> — срок истёк", C.GREEN))
        for uid, until in list(store["bans"].items()):
            if until and until <= now:
                try:
                    await guild.unban(discord.Object(id=int(uid)), reason="Срок бана истёк")
                except discord.HTTPException:
                    pass
                del store["bans"][uid]
                changed = True
                await log(guild, C.CH_PUNISH_LOG, card("🔓 Бан снят", f"<@{uid}> — срок истёк", C.GREEN))
        if changed:
            store.save()

    @timers.before_loop
    async def _wait(self):
        await self.wait_until_ready()

    # ── события ──
    async def on_member_join(self, m: discord.Member):
        if m.guild.id != self.guild_id:
            return
        r = role(m.guild, C.BOTS if m.bot else C.NEWBIE)
        if r:
            try:
                await m.add_roles(r, reason="Автороль")
            except discord.HTTPException:
                pass
        if str(m.id) in store["mutes"] and (r := role(m.guild, C.MUTE)):
            await m.add_roles(r, reason="Мут не истёк (перезаход)")
        e = card("📥 Зашёл на сервер", f"{m.mention} `{m}`\nАккаунт создан <t:{int(m.created_at.timestamp())}:R>",
                 C.GREEN)
        await log(m.guild, C.CH_SERVER_LOG, e)
        if not m.bot and isinstance(ch := chan(m.guild, C.CH_VERIFY), discord.TextChannel):
            await ch.send(TX.WELCOME_JOIN.format(user=m.mention), delete_after=600,
                          allowed_mentions=discord.AllowedMentions(users=True))

    async def on_member_remove(self, m: discord.Member):
        if m.guild.id == self.guild_id:
            await log(m.guild, C.CH_SERVER_LOG, card("📤 Вышел с сервера", f"{m.mention} `{m}`", C.DARK))

    async def on_member_update(self, before: discord.Member, after: discord.Member):
        if after.guild.id != self.guild_id:
            return
        added = [r.mention for r in after.roles if r not in before.roles]
        removed = [r.mention for r in before.roles if r not in after.roles]
        if added or removed:
            desc = f"{after.mention}\n" + (f"➕ {' '.join(added)}\n" if added else "") + \
                   (f"➖ {' '.join(removed)}" if removed else "")
            await log(after.guild, C.CH_SERVER_LOG, card("🎭 Изменены роли", desc, C.GOLD))
        if before.nick != after.nick:
            await log(after.guild, C.CH_SERVER_LOG,
                      card("✏️ Ник изменён", f"{after.mention}: `{before.nick}` → `{after.nick}`", C.GOLD))

    async def on_message_delete(self, msg: discord.Message):
        if not msg.guild or msg.guild.id != self.guild_id or msg.author.bot:
            return
        e = card("🗑 Сообщение удалено",
                 f"Автор: {msg.author.mention}\nКанал: {msg.channel.mention}\n\n{msg.content[:3500] or '*без текста*'}",
                 C.DARK)
        await log(msg.guild, C.CH_SERVER_LOG, e)

    async def on_message_edit(self, before: discord.Message, after: discord.Message):
        if not after.guild or after.guild.id != self.guild_id or after.author.bot or before.content == after.content:
            return
        e = card("✏️ Сообщение изменено",
                 f"Автор: {after.author.mention} • [перейти]({after.jump_url})\n\n"
                 f"**Было:** {before.content[:1700]}\n**Стало:** {after.content[:1700]}", C.DARK)
        await log(after.guild, C.CH_SERVER_LOG, e)

    async def on_message(self, msg: discord.Message):
        if not msg.guild or msg.guild.id != self.guild_id or msg.author.bot or not isinstance(msg.author, discord.Member):
            return
        if msg.channel.id == store["channels"].get(C.CH_IDEAS):
            for em in ("👍", "👎"):
                await msg.add_reaction(em)
        if staff_level(msg.author) or not self.is_filtered(msg.channel):
            return
        reason = None
        text = normalize(msg.content)
        if any(p.search(text) for p in self.mat):
            reason = "мат в общих каналах"
        else:
            letters = [c for c in msg.content if c.isalpha()]
            if len(letters) >= C.CAPS_MIN_LETTERS and sum(c.isupper() for c in letters) / len(letters) >= C.CAPS_RATIO:
                reason = "капс"
        if reason:
            try:
                await msg.delete()
            except discord.HTTPException:
                return
            await msg.channel.send(f"{msg.author.mention}, сообщение удалено: **{reason}**. Соблюдай правила.",
                                   delete_after=8, allowed_mentions=discord.AllowedMentions(users=True))
            await log(msg.guild, C.CH_SERVER_LOG,
                      card("🛡 Автомодерация", f"{msg.author.mention} в {msg.channel.mention}: {reason}\n\n{msg.content[:1500]}"))

    def is_filtered(self, channel) -> bool:
        cat_id = getattr(channel, "category_id", None)
        for c in C.CATEGORIES:
            if c.get("filtered") and store["channels"].get(c["key"]) == cat_id:
                return True
        return False


_LOOKALIKE = str.maketrans("aeopcxykmth3ё", "аеорсхукмтнзе")


def normalize(s: str) -> str:
    s = s.lower().translate(_LOOKALIKE)
    return re.sub(r"(.)\1{2,}", r"\1\1", s)


# ═════════════════════════════════ Настройка сервера ═════════════════════════════════

async def setup_guild(guild: discord.Guild, say):
    warnings = []
    me = guild.me
    if not me.guild_permissions.administrator:
        raise RuntimeError("У бота нет права «Администратор». Пригласите его заново с этим правом.")

    # 1. Роли
    await say("1/6 Роли…")
    roles = {}
    for spec in C.ROLES:
        r = role(guild, spec["name"])
        p = discord.Permissions(**perms(**spec["perms"]))
        kw = dict(colour=discord.Colour(spec["color"]), hoist=spec["hoist"], permissions=p,
                  mentionable=spec["name"] not in (C.MUTE, C.NEWBIE, C.BOTS))
        if r is None:
            r = await guild.create_role(name=spec["name"], reason="Настройка СССР РП", **kw)
        elif r < me.top_role and not r.managed:
            if (r.colour.value, r.hoist, r.permissions, r.mentionable) != (spec["color"], spec["hoist"], p, kw["mentionable"]):
                await r.edit(reason="Настройка СССР РП", **kw)
        else:
            warnings.append(f"Роль «{r.name}» выше роли бота — её права не обновлены.")
        roles[spec["name"]] = r
    # порядок: наши роли сразу под ролью бота, в порядке из config
    ordered = [roles[s["name"]] for s in C.ROLES if roles[s["name"]] < me.top_role]
    top = me.top_role.position - 1
    positions = {r: top - i for i, r in enumerate(ordered)}
    if any(r.position != p for r, p in positions.items()):
        try:
            await guild.edit_role_positions(positions, reason="Порядок ролей СССР РП")
        except discord.HTTPException as e:
            warnings.append(f"Не удалось упорядочить роли: {e}")

    await guild.default_role.edit(permissions=discord.Permissions(**perms(**C.EVERYONE_PERMS)),
                                  reason="Настройка СССР РП")

    # 2. Категории и каналы
    await say("2/6 Категории и каналы (это самый долгий шаг)…")
    for ci, cat in enumerate(C.CATEGORIES):
        ow = to_overwrites(guild, overwrite_spec(cat))
        category = chan(guild, cat["key"])
        if not isinstance(category, discord.CategoryChannel):
            category = discord.utils.get(guild.categories, name=cat["name"])
        if category is None:
            category = await guild.create_category(cat["name"], overwrites=ow, reason="Настройка СССР РП")
        elif category.name != cat["name"] or category.overwrites != ow:
            await category.edit(name=cat["name"], overwrites=ow, reason="Настройка СССР РП")
        store["channels"][cat["key"]] = category.id
        for ch in cat["channels"]:
            key = f"{cat['key']}.{ch['key']}"
            ow = to_overwrites(guild, overwrite_spec(cat, ch))
            obj = chan(guild, key)
            if obj is None:
                obj = discord.utils.get(category.channels, name=ch["name"])
            if ch["type"] == "voice":
                if obj is None:
                    obj = await category.create_voice_channel(ch["name"], overwrites=ow, reason="Настройка СССР РП")
                elif (obj.name, obj.category_id, obj.overwrites) != (ch["name"], category.id, ow):
                    await obj.edit(name=ch["name"], category=category, overwrites=ow)
            else:
                kw = dict(topic=ch.get("topic", ""), slowmode_delay=ch.get("slowmode", 0), overwrites=ow)
                if obj is None:
                    obj = await category.create_text_channel(ch["name"], reason="Настройка СССР РП", **kw)
                elif (obj.name, obj.category_id, obj.overwrites, obj.topic or "", obj.slowmode_delay) != \
                        (ch["name"], category.id, ow, kw["topic"], kw["slowmode_delay"]):
                    await obj.edit(name=ch["name"], category=category, **kw)
            store["channels"][key] = obj.id
        store.save()
        await say(f"2/6 Каналы: {ci + 1}/{len(C.CATEGORIES)} — {cat['name']}")

    # 3. Тексты и панели
    await say("3/6 Тексты, правила и кнопки…")
    for cat in C.CATEGORIES:
        for ch in cat["channels"]:
            if ch.get("post"):
                key = f"{cat['key']}.{ch['key']}"
                await publish(guild, key, ch["post"], cat)

    # 4. Автомодерация Discord
    await say("4/6 Автомодерация…")
    try:
        await setup_automod(guild)
    except discord.HTTPException as e:
        warnings.append(f"Автомодерация Discord: {e}")

    # 5. Роли участникам
    await say("5/6 Роли участникам, у которых их нет…")
    newbie, bots, citizen = role(guild, C.NEWBIE), role(guild, C.BOTS), role(guild, C.CITIZEN)
    for m in guild.members:
        try:
            if m.bot and bots and bots not in m.roles and not m == me:
                await m.add_roles(bots)
            elif not m.bot and citizen not in m.roles and newbie not in m.roles:
                await m.add_roles(newbie)
        except discord.HTTPException:
            pass

    await say("6/6 Готово!")
    store.save()
    return warnings


POSTS = {
    "rules_server": TX.RULES_SERVER, "rules_game": TX.RULES_GAME, "download": TX.DOWNLOAD,
    "ideas": TX.IDEAS, "bugs": TX.BUGS, "complaints": TX.COMPLAINTS, "appeals": TX.APPEALS,
    "charter": TX.CHARTER, "opg_ranks": TX.OPG_RANKS, "territory": TX.TERRITORY,
}
PANELS = {
    "verify": (TX.VERIFY, lambda: VerifyView()),
    "tickets": (TX.TICKETS, lambda: TicketPanel()),
    "apply_org": (TX.APPLY_ORG, lambda: OrgPanel()),
    "apply_admin": (TX.APPLY_ADMIN, lambda: SimpleApplyPanel("admin")),
    "apply_tester": (TX.APPLY_TESTER, lambda: SimpleApplyPanel("tester")),
}


async def publish(guild, key, post, cat=None, repost=False):
    """Публикует текст/панель или обновляет ранее опубликованное сообщение."""
    ch = chan(guild, key)
    if not isinstance(ch, discord.TextChannel):
        return
    if post in PANELS:
        blocks, mk = PANELS[post]
        view = mk()
    else:
        blocks, view = POSTS[post], None
    embeds = embeds_from(blocks, C.GOLD if post in ("charter", "opg_ranks") else C.RED)
    rec = store["messages"].get(key)
    msg = None
    if rec:
        try:
            msg = await ch.fetch_message(int(rec[1]))
        except discord.HTTPException:
            msg = None
    if msg and repost:
        try:
            await msg.delete()
        except discord.HTTPException:
            pass
        msg = None
    if msg:
        if msg.author.id == guild.me.id:
            await msg.edit(embeds=embeds, view=view)
        return  # сообщение уже есть (возможно, лидер заменил его своим) — не дублируем
    msg = await ch.send(embeds=embeds, view=view)
    if post not in PANELS or post in ("verify", "tickets"):
        try:
            await msg.pin()
        except discord.HTTPException:
            pass
    store["messages"][key] = [ch.id, msg.id]
    store.save()


async def setup_automod(guild):
    existing = {r.name for r in await guild.fetch_automod_rules()}
    log_ch = chan(guild, C.CH_SERVER_LOG)
    exempt = [r for n in (C.FOUNDER, C.HEAD_ADMIN, C.ADMIN, C.MOD, C.BOTS) if (r := role(guild, n))]
    alert = [discord.AutoModRuleAction(channel_id=log_ch.id)] if log_ch else []
    rules = [
        ("СССР РП: приглашения", discord.AutoModTrigger(type=discord.AutoModRuleTriggerType.keyword,
                                                       regex_patterns=[C.INVITE_REGEX]),
         "Приглашения на другие серверы запрещены."),
        ("СССР РП: спам", discord.AutoModTrigger(type=discord.AutoModRuleTriggerType.spam), None),
        ("СССР РП: упоминания", discord.AutoModTrigger(type=discord.AutoModRuleTriggerType.mention_spam,
                                                      mention_limit=C.MENTION_LIMIT, mention_raid_protection=True),
         "Слишком много упоминаний."),
    ]
    for name, trig, text in rules:
        if name in existing:
            continue
        actions = [discord.AutoModRuleAction(custom_message=text)] if text else [discord.AutoModRuleAction()]
        if trig.type != discord.AutoModRuleTriggerType.spam:
            actions += alert
        await guild.create_automod_rule(name=name, event_type=discord.AutoModRuleEventType.message_send,
                                        trigger=trig, actions=actions, enabled=True, exempt_roles=exempt)


# ═════════════════════════════════ Верификация ═════════════════════════════════

NICK_RE = re.compile(r"^[A-Za-zА-Яа-яЁё0-9_.\- ]{3,32}$")


async def verify_member(inter: discord.Interaction, nick: str):
    m, g = inter.user, inter.guild
    nick = nick.strip()
    if not NICK_RE.match(nick):
        return await inter.response.send_message(
            "Ник должен быть от 3 до 32 символов: буквы, цифры, `_`, `-`, точка.", ephemeral=True)
    citizen, newbie = role(g, C.CITIZEN), role(g, C.NEWBIE)
    already = citizen in m.roles
    try:
        await m.add_roles(citizen, reason=f"Верификация: {nick}")
        if newbie in m.roles:
            await m.remove_roles(newbie, reason="Верификация")
    except discord.HTTPException:
        return await inter.response.send_message("Не удалось выдать роль — сообщите администрации.", ephemeral=True)
    try:
        await m.edit(nick=nick, reason="Игровой ник")
        renamed = ""
    except discord.HTTPException:
        renamed = "\n(Ник на сервере поменять не удалось — поменяй его сам.)"
    await inter.response.send_message(f"✅ Готово, товарищ **{nick}**! Каналы открыты.{renamed}", ephemeral=True)
    if not already and isinstance(ch := chan(g, C.CH_WELCOME), discord.TextChannel):
        await ch.send(embeds=embeds_from(TX.WELCOME_CITIZEN, C.GOLD, user=m.mention, nick=nick))
    await log(g, C.CH_SERVER_LOG, card("✅ Верификация", f"{m.mention} → ник **{nick}**", C.GREEN))


class VerifyModal(discord.ui.Modal, title="Верификация"):
    nick = discord.ui.TextInput(label="Игровой ник (точно как в игре)", placeholder="Ivan_Petrov",
                                min_length=3, max_length=32)

    async def on_submit(self, inter):
        await verify_member(inter, str(self.nick))


class VerifyView(discord.ui.View):
    def __init__(self):
        super().__init__(timeout=None)

    @discord.ui.button(label="Пройти верификацию", emoji="✅", style=discord.ButtonStyle.success,
                       custom_id="verify:start")
    async def start(self, inter, _):
        await inter.response.send_modal(VerifyModal())


# ═════════════════════════════════ Тикеты ═════════════════════════════════

class TicketPanel(discord.ui.View):
    def __init__(self):
        super().__init__(timeout=None)

    @discord.ui.select(custom_id="ticket:open", placeholder="Выбери тип обращения…",
                       options=[discord.SelectOption(label=t["label"], value=t["key"], emoji=t["emoji"])
                                for t in C.TICKET_TYPES])
    async def open(self, inter: discord.Interaction, select: discord.ui.Select):
        t = C.TICKET_TYPE_BY_KEY[select.values[0]]
        g, m = inter.guild, inter.user
        mine = [cid for cid, rec in store["tickets"].items() if rec["user"] == m.id and g.get_channel(int(cid))]
        if len(mine) >= C.MAX_OPEN_TICKETS:
            return await inter.response.send_message(
                f"У тебя уже открыто тикетов: {len(mine)}. Закрой старый: " +
                " ".join(f"<#{c}>" for c in mine), ephemeral=True)
        category = chan(g, C.TICKET_CATEGORY)
        store.d["ticket_no"] += 1
        no = store["ticket_no"]
        ow = {g.default_role: discord.PermissionOverwrite(view_channel=False),
              m: discord.PermissionOverwrite(view_channel=True, send_messages=True, attach_files=True,
                                             read_message_history=True),
              g.me: discord.PermissionOverwrite(view_channel=True, send_messages=True)}
        for name in t["staff"]:
            if r := role(g, name):
                ow[r] = discord.PermissionOverwrite(view_channel=True, send_messages=True, read_message_history=True)
        ch = await g.create_text_channel(f"{t['emoji']}・тикет-{no:04d}", category=category, overwrites=ow,
                                         topic=f"{t['label']} • {m} ({m.id})", reason="Тикет")
        store["tickets"][str(ch.id)] = {"user": m.id, "type": t["key"], "no": no}
        store.save()
        staff_ping = " ".join(r.mention for n in t["staff"] if (r := role(g, n)))
        e = card(f"{t['emoji']} Тикет №{no:04d}: {t['label']}", TX.TICKET_INTRO[t["key"]])
        await ch.send(content=f"{m.mention} {staff_ping}", embed=e, view=TicketControl(),
                      allowed_mentions=discord.AllowedMentions(users=True, roles=True))
        await inter.response.send_message(f"Тикет создан: {ch.mention}", ephemeral=True)
        if t["key"] == "admin":
            await log(g, C.CH_ADMIN_COMPLAINTS, card("🔒 Новая жалоба на администрацию",
                                                      f"От {m.mention}: {ch.mention}"))
        await log(g, C.CH_SERVER_LOG, card("🎫 Тикет открыт", f"№{no:04d} {t['label']} — {m.mention}", C.GOLD))


class TicketControl(discord.ui.View):
    def __init__(self):
        super().__init__(timeout=None)

    @discord.ui.button(label="Закрыть тикет", emoji="🔒", style=discord.ButtonStyle.danger, custom_id="ticket:close")
    async def close(self, inter: discord.Interaction, _):
        rec = store["tickets"].get(str(inter.channel_id))
        if not rec:
            return await inter.response.send_message("Это не тикет.", ephemeral=True)
        if inter.user.id != rec["user"] and staff_level(inter.user) < 1:
            return await inter.response.send_message("Закрыть может автор или администрация.", ephemeral=True)
        await inter.response.send_message("Тикет закроется через 5 секунд…")
        del store["tickets"][str(inter.channel_id)]
        store.save()
        await log(inter.guild, C.CH_SERVER_LOG,
                  card("🎫 Тикет закрыт", f"№{rec['no']:04d} — <@{rec['user']}>, закрыл {inter.user.mention}", C.DARK))
        await asyncio.sleep(5)
        try:
            await inter.channel.delete(reason="Тикет закрыт")
        except discord.HTTPException:
            pass


# ═════════════════════════════════ Заявки ═════════════════════════════════

APPLY_TARGET_ROLES = {"admin": [C.MOD], "tester": [C.DEV]}


def can_decide(m: discord.Member, kind: str, target: str) -> bool:
    lvl = staff_level(m)
    if kind == "org":
        return lvl >= 2 or has_role(m, C.FACTION_BY_KEY[target]["leader"])
    if kind == "tester":
        return lvl >= 2 or has_role(m, C.DEV)
    return lvl >= 2 if kind == "lead" else lvl >= 3


def member_faction(m: discord.Member):
    for f in C.FACTIONS:
        if has_role(m, f["member"]):
            return f
    return None


class ApplyModal(discord.ui.Modal):
    def __init__(self, kind, target="x"):
        title, fields = TX.APPLY_FORMS[kind]
        if target in C.FACTION_BY_KEY:
            title = f"{title}: {C.FACTION_BY_KEY[target]['member']}"[:45]
        super().__init__(title=title, timeout=600)
        self.kind, self.target = kind, target
        self.inputs = []
        for label, ph, long in fields:
            ti = discord.ui.TextInput(label=label, placeholder=ph or None, max_length=600 if long else 100,
                                      style=discord.TextStyle.paragraph if long else discord.TextStyle.short)
            self.add_item(ti)
            self.inputs.append(ti)

    async def on_submit(self, inter: discord.Interaction):
        g, m = inter.guild, inter.user
        f = C.FACTION_BY_KEY.get(self.target)
        title = TX.APPLY_FORMS[self.kind][0] + (f" — {f['emoji']} {f['member']}" if f else "")
        e = card(f"📝 {title}", f"От: {m.mention} (`{m}`)", C.GOLD)
        for ti in self.inputs:
            e.add_field(name=ti.label, value=str(ti.value)[:1024] or "—", inline=len(str(ti.value)) < 40)
        e.set_thumbnail(url=m.display_avatar.url)
        view = discord.ui.View(timeout=None)
        view.add_item(Decision("ok", self.kind, self.target, m.id))
        view.add_item(Decision("no", self.kind, self.target, m.id))
        key = C.CH_APPLY[self.kind]
        ch = chan(g, key)
        if not isinstance(ch, discord.TextChannel):
            return await inter.response.send_message("Канал заявок не найден — сообщите администрации.",
                                                     ephemeral=True)
        ping = ""
        if f and (lr := role(g, f["leader"])):
            ping = lr.mention
        await ch.send(content=ping or None, embed=e, view=view,
                      allowed_mentions=discord.AllowedMentions(roles=True))
        await inter.response.send_message("✅ Заявка отправлена! Ответ придёт в личные сообщения "
                                          "(если они открыты) и появится под заявкой.", ephemeral=True)
        post = {"org": "apply_org", "admin": "apply_admin", "tester": "apply_tester"}.get(self.kind)
        if post:  # панель всегда внизу канала
            await publish(g, key, post, repost=True)


def check_can_apply(inter, kind, target) -> str | None:
    m = inter.user
    if not has_role(m, C.CITIZEN):
        return "Сначала пройди верификацию."
    if kind == "org":
        f = C.FACTION_BY_KEY[target]
        if has_role(m, f["member"]):
            return "Ты уже состоишь в этой организации."
        if C.ONE_FACTION_ONLY and (cur := member_faction(m)):
            return f"Ты уже состоишь в «{cur['member']}». Сначала уволься оттуда."
    return None


class OrgPanel(discord.ui.View):
    def __init__(self):
        super().__init__(timeout=None)

    @discord.ui.select(custom_id="apply:org", placeholder="Подать заявку в организацию…",
                       options=[discord.SelectOption(label=f["member"], value=f["key"], emoji=f["emoji"],
                                                     description=f"{f['city']} • лидер: {f['leader']}"[:100])
                                for f in C.FACTIONS])
    async def org(self, inter, select):
        target = select.values[0]
        if err := check_can_apply(inter, "org", target):
            return await inter.response.send_message(err, ephemeral=True)
        await inter.response.send_modal(ApplyModal("org", target))

    @discord.ui.button(label="Заявка на лидерство", emoji="⭐", style=discord.ButtonStyle.primary,
                       custom_id="apply:lead")
    async def lead(self, inter, _):
        if err := check_can_apply(inter, "lead", "x"):
            return await inter.response.send_message(err, ephemeral=True)
        v = discord.ui.View(timeout=300)
        sel = discord.ui.Select(placeholder="Лидером какой организации?", options=[
            discord.SelectOption(label=f["leader"], value=f["key"], emoji=f["emoji"]) for f in C.FACTIONS])

        async def cb(i2):
            await i2.response.send_modal(ApplyModal("lead", sel.values[0]))
        sel.callback = cb
        v.add_item(sel)
        await inter.response.send_message("Выбери организацию:", view=v, ephemeral=True)


class SimpleApplyPanel(discord.ui.View):
    def __init__(self, kind):
        super().__init__(timeout=None)
        b = discord.ui.Button(label="Подать заявку", emoji="📝", style=discord.ButtonStyle.success,
                              custom_id=f"apply:{kind}")

        async def cb(inter):
            if err := check_can_apply(inter, kind, "x"):
                return await inter.response.send_message(err, ephemeral=True)
            await inter.response.send_modal(ApplyModal(kind))
        b.callback = cb
        self.add_item(b)


class Decision(discord.ui.DynamicItem[discord.ui.Button],
               template=r"app:(?P<act>ok|no):(?P<kind>org|lead|admin|tester):(?P<target>\w+):(?P<uid>\d+)"):
    def __init__(self, act, kind, target, uid):
        super().__init__(discord.ui.Button(
            label="Принять" if act == "ok" else "Отклонить", emoji="✅" if act == "ok" else "❌",
            style=discord.ButtonStyle.success if act == "ok" else discord.ButtonStyle.danger,
            custom_id=f"app:{act}:{kind}:{target}:{uid}"))
        self.act, self.kind, self.target, self.uid = act, kind, target, int(uid)

    @classmethod
    async def from_custom_id(cls, inter, item, match):
        return cls(match["act"], match["kind"], match["target"], match["uid"])

    async def callback(self, inter: discord.Interaction):
        g = inter.guild
        if not can_decide(inter.user, self.kind, self.target):
            return await inter.response.send_message("Решение принимает лидер организации или администрация.",
                                                     ephemeral=True)
        applicant = g.get_member(self.uid)
        f = C.FACTION_BY_KEY.get(self.target)
        e = inter.message.embeds[0] if inter.message.embeds else card("Заявка")
        if self.act == "ok":
            if applicant is None:
                return await inter.response.send_message("Игрок уже покинул сервер.", ephemeral=True)
            names = {"org": [f["member"]] if f else [], "lead": [f["leader"], f["member"]] if f else []}.get(
                self.kind, APPLY_TARGET_ROLES.get(self.kind, []))
            try:
                await applicant.add_roles(*[r for n in names if (r := role(g, n))],
                                          reason=f"Заявка одобрена: {inter.user}")
            except discord.HTTPException:
                return await inter.response.send_message("Не удалось выдать роль (проверьте порядок ролей).",
                                                         ephemeral=True)
            e.color, verdict = C.GREEN, f"✅ Принята — {inter.user.display_name}"
        else:
            e.color, verdict = C.DARK, f"❌ Отклонена — {inter.user.display_name}"
        e.set_footer(text=f"{verdict} • {C.FOOTER}")
        await inter.response.edit_message(embed=e, view=None)
        if applicant:
            try:
                await applicant.send(f"Твоя заявка «{TX.APPLY_FORMS[self.kind][0]}» на сервере «{g.name}»: {verdict}")
            except discord.HTTPException:
                pass
        if f and self.act == "ok":
            await hr_log(g, f, f"✅ {applicant.mention} принят(а) в «{f['member']}»"
                               + (" **на пост лидера**" if self.kind == "lead" else "") + f" • {inter.user.mention}")


async def hr_log(guild, f, text):
    await log(guild, f"{f['key']}.hr", card("🗂 Кадры", text, C.GOLD))


# ═════════════════════════════════ Команды ═════════════════════════════════

FACTION_CHOICES = [app_commands.Choice(name=f["member"], value=f["key"]) for f in C.FACTIONS]


def register_commands(tree: app_commands.CommandTree):

    @tree.command(name="настроить-сервер", description="Создать/обновить роли, каналы, права и тексты СССР РП")
    async def setup_cmd(inter: discord.Interaction):
        if staff_level(inter.user) < 4:
            return await inter.response.send_message("Только владелец сервера или Основатель.", ephemeral=True)
        await inter.response.send_message("☭ Начинаю настройку сервера. Это займёт несколько минут…")
        status = await inter.original_response()
        ch = inter.channel

        async def say(text):
            try:
                await status.edit(content=f"☭ {text}")
            except discord.HTTPException:   # канал мог быть переименован/пересоздан
                pass
        try:
            warnings = await setup_guild(inter.guild, say)
        except Exception as e:  # noqa: BLE001
            return await ch.send(f"❌ Ошибка настройки: `{e}`\nИсправьте и запустите команду снова — "
                                 "бот продолжит с того места, где остановился.")
        text = "✅ **Сервер настроен!**"
        if warnings:
            text += "\n\n⚠️ Предупреждения:\n" + "\n".join(f"• {w}" for w in warnings)
        try:
            await ch.send(text)
        except discord.HTTPException:
            pass

    @tree.command(name="верификация", description="Указать игровой ник и получить роль «Гражданин»")
    @app_commands.describe(ник="Игровой ник, точно как в игре")
    async def verify_cmd(inter: discord.Interaction, ник: str):
        await verify_member(inter, ник)

    # ── организации ──
    async def faction_guard(inter, org):
        f = C.FACTION_BY_KEY[org]
        if staff_level(inter.user) >= 2 or has_role(inter.user, f["leader"]):
            return f
        await inter.response.send_message(f"Только {f['leader']} или администрация.", ephemeral=True)
        return None

    @tree.command(name="принять", description="Принять игрока в организацию (для лидеров)")
    @app_commands.choices(организация=FACTION_CHOICES)
    async def hire(inter: discord.Interaction, игрок: discord.Member, организация: app_commands.Choice[str]):
        if not (f := await faction_guard(inter, организация.value)):
            return
        if C.ONE_FACTION_ONLY and (cur := member_faction(игрок)) and cur is not f:
            return await inter.response.send_message(f"{игрок.mention} уже в «{cur['member']}».", ephemeral=True)
        await игрок.add_roles(role(inter.guild, f["member"]), reason=f"Принят: {inter.user}")
        await inter.response.send_message(f"✅ {игрок.mention} принят(а) в «{f['member']}».")
        await hr_log(inter.guild, f, f"✅ {игрок.mention} принят(а) • {inter.user.mention}")

    @tree.command(name="уволить", description="Уволить игрока из организации (для лидеров)")
    @app_commands.choices(организация=FACTION_CHOICES)
    async def fire(inter: discord.Interaction, игрок: discord.Member, организация: app_commands.Choice[str],
                   причина: str = "—"):
        if not (f := await faction_guard(inter, организация.value)):
            return
        rs = [role(inter.guild, f["member"])]
        if staff_level(inter.user) >= 2:
            rs.append(role(inter.guild, f["leader"]))
        await игрок.remove_roles(*[r for r in rs if r], reason=f"Уволен: {inter.user}: {причина}")
        await inter.response.send_message(f"🚪 {игрок.mention} уволен(а) из «{f['member']}». Причина: {причина}")
        await hr_log(inter.guild, f, f"🚪 {игрок.mention} уволен(а) • {inter.user.mention}\nПричина: {причина}")

    # ── модерация ──
    async def mod_guard(inter, target: discord.Member | None, level: int):
        if staff_level(inter.user) < level:
            names = {1: C.MOD, 2: C.ADMIN, 3: C.HEAD_ADMIN}
            await inter.response.send_message(f"Нужна роль «{names.get(level, C.FOUNDER)}» или выше.", ephemeral=True)
            return False
        if target is not None and (staff_level(target) >= staff_level(inter.user) or target.bot):
            await inter.response.send_message("Нельзя наказать этого участника.", ephemeral=True)
            return False
        return True

    async def punish_log(g, title, who, by, reason, until=None, color=C.RED):
        e = card(title, color=color)
        e.add_field(name="Кого", value=f"{who.mention if hasattr(who, 'mention') else who}")
        e.add_field(name="Кто", value=by.mention)
        if until is not False:
            e.add_field(name="На сколько", value=fmt_until(until))
        e.add_field(name="За что", value=reason, inline=False)
        await log(g, C.CH_PUNISH_LOG, e)

    async def do_ban(g, member, by, reason, days):
        until = time.time() + days * 86400 if days else 0
        try:
            await member.send(f"Ты забанен(а) на сервере «{g.name}» {('до ' + dt.datetime.fromtimestamp(until).strftime('%d.%m.%Y %H:%M')) if until else 'навсегда'}. Причина: {reason}")
        except discord.HTTPException:
            pass
        await g.ban(member, reason=f"{by}: {reason}", delete_message_seconds=0)
        if until:
            store["bans"][str(member.id)] = until
            store.save()
        await punish_log(g, "⛔ Бан", member, by, reason, until)

    @tree.command(name="пред", description="Выдать предупреждение")
    async def warn(inter: discord.Interaction, игрок: discord.Member, причина: str):
        if not await mod_guard(inter, игрок, 1):
            return
        w = store["warns"].setdefault(str(игрок.id), [])
        w.append({"by": inter.user.id, "reason": причина, "at": int(time.time())})
        store.save()
        n = len(w)
        await inter.response.send_message(f"⚠️ {игрок.mention} получает предупреждение ({n}/{C.WARN_LIMIT}). "
                                          f"Причина: {причина}", allowed_mentions=discord.AllowedMentions(users=True))
        await punish_log(inter.guild, f"⚠️ Предупреждение {n}/{C.WARN_LIMIT}", игрок, inter.user, причина, False,
                         C.GOLD)
        if n >= C.WARN_LIMIT:
            store["warns"][str(игрок.id)] = []
            store.save()
            await do_ban(inter.guild, игрок, inter.user, f"{C.WARN_LIMIT} предупреждения", C.WARN_BAN_DAYS)
            await inter.followup.send(f"⛔ {игрок.mention}: {C.WARN_LIMIT} предупреждения — бан на {C.WARN_BAN_DAYS} дня.")

    @tree.command(name="преды", description="Посмотреть предупреждения игрока")
    async def warns(inter: discord.Interaction, игрок: discord.Member):
        if not await mod_guard(inter, None, 1):
            return
        w = store["warns"].get(str(игрок.id), [])
        text = "\n".join(f"{i + 1}. <t:{x['at']}:d> — {x['reason']} (<@{x['by']}>)" for i, x in enumerate(w)) or "Нет."
        await inter.response.send_message(embed=card(f"Предупреждения: {игрок.display_name}", text, C.GOLD),
                                          ephemeral=True)

    @tree.command(name="снять-пред", description="Снять последнее предупреждение")
    async def unwarn(inter: discord.Interaction, игрок: discord.Member):
        if not await mod_guard(inter, None, 2):
            return
        w = store["warns"].get(str(игрок.id), [])
        if not w:
            return await inter.response.send_message("Предупреждений нет.", ephemeral=True)
        w.pop()
        store.save()
        await inter.response.send_message(f"✅ С {игрок.mention} снято одно предупреждение ({len(w)}/{C.WARN_LIMIT}).")
        await punish_log(inter.guild, "✅ Снято предупреждение", игрок, inter.user, "—", False, C.GREEN)

    @tree.command(name="мут", description="Запретить писать и говорить на время")
    @app_commands.describe(минуты="0 — бессрочно")
    async def mute(inter: discord.Interaction, игрок: discord.Member, минуты: app_commands.Range[int, 0, 40320],
                   причина: str):
        if not await mod_guard(inter, игрок, 1):
            return
        await игрок.add_roles(role(inter.guild, C.MUTE), reason=f"{inter.user}: {причина}")
        until = time.time() + минуты * 60 if минуты else 0
        store["mutes"][str(игрок.id)] = until
        store.save()
        await inter.response.send_message(f"🔇 {игрок.mention} в муте {('до ' + fmt_until(until)) if until else 'бессрочно'}. "
                                          f"Причина: {причина}")
        await punish_log(inter.guild, "🔇 Мут", игрок, inter.user, причина, until, C.GOLD)

    @tree.command(name="размут", description="Снять мут")
    async def unmute(inter: discord.Interaction, игрок: discord.Member):
        if not await mod_guard(inter, игрок, 1):
            return
        await игрок.remove_roles(role(inter.guild, C.MUTE), reason=str(inter.user))
        store["mutes"].pop(str(игрок.id), None)
        store.save()
        await inter.response.send_message(f"🔈 {игрок.mention} может снова писать.")
        await punish_log(inter.guild, "🔈 Мут снят", игрок, inter.user, "—", False, C.GREEN)

    @tree.command(name="кик", description="Выгнать с сервера")
    async def kick(inter: discord.Interaction, игрок: discord.Member, причина: str):
        if not await mod_guard(inter, игрок, 2):
            return
        await inter.guild.kick(игрок, reason=f"{inter.user}: {причина}")
        await inter.response.send_message(f"👢 {игрок} выгнан(а). Причина: {причина}")
        await punish_log(inter.guild, "👢 Кик", игрок, inter.user, причина, False)

    @tree.command(name="бан", description="Забанить")
    @app_commands.describe(дней="0 — навсегда")
    async def ban(inter: discord.Interaction, игрок: discord.Member, дней: app_commands.Range[int, 0, 365],
                  причина: str):
        if not await mod_guard(inter, игрок, 2):
            return
        await inter.response.send_message(f"⛔ {игрок} забанен(а) {'на ' + str(дней) + ' дн.' if дней else 'навсегда'}. "
                                          f"Причина: {причина}")
        await do_ban(inter.guild, игрок, inter.user, причина, дней)

    @tree.command(name="разбан", description="Разбанить по ID")
    async def unban(inter: discord.Interaction, id_игрока: str):
        if not await mod_guard(inter, None, 2):
            return
        try:
            await inter.guild.unban(discord.Object(id=int(id_игрока)), reason=str(inter.user))
        except (ValueError, discord.HTTPException):
            return await inter.response.send_message("Бан не найден.", ephemeral=True)
        store["bans"].pop(id_игрока, None)
        store.save()
        await inter.response.send_message(f"🔓 <@{id_игрока}> разбанен(а).")
        await punish_log(inter.guild, "🔓 Разбан", f"<@{id_игрока}>", inter.user, "—", False, C.GREEN)


# ═════════════════════════════════ Проверка и документация (без Discord) ═════════════════════════════════

def check_config():
    errors = []
    role_names = [r["name"] for r in C.ROLES]
    if len(set(role_names)) != len(role_names):
        errors.append("Повторяются имена ролей")
    known = set(role_names) | {C.EVERYONE}
    keys, n_channels = set(), 0
    for cat in C.CATEGORIES:
        if cat["key"] in keys:
            errors.append(f"Повтор ключа категории {cat['key']}")
        keys.add(cat["key"])
        for ch in [None] + cat["channels"]:
            spec = overwrite_spec(cat, ch)
            for r, p in spec.items():
                if r not in known:
                    errors.append(f"{cat['key']}: неизвестная роль «{r}»")
            if ch:
                n_channels += 1
                k = f"{cat['key']}.{ch['key']}"
                if k in keys:
                    errors.append(f"Повтор ключа {k}")
                keys.add(k)
                if len(ch["name"]) > 100:
                    errors.append(f"{k}: имя длиннее 100")
                if ch["type"] == "text" and (ch["name"] != ch["name"].lower() or " " in ch["name"]):
                    errors.append(f"{k}: имя текстового канала должно быть строчными буквами и без пробелов")
                if ch.get("post") and ch["post"] not in POSTS and ch["post"] not in PANELS:
                    errors.append(f"{k}: неизвестный post «{ch['post']}»")
        if len(cat["channels"]) > 50:
            errors.append(f"{cat['key']}: больше 50 каналов")
    for k in [C.CH_SERVER_LOG, C.CH_PUNISH_LOG, C.CH_VERIFY, C.CH_WELCOME, C.CH_IDEAS, C.CH_ADMIN_COMPLAINTS,
              C.TICKET_CATEGORY, *C.CH_APPLY.values(), *[f"{f['key']}.hr" for f in C.FACTIONS]]:
        if k not in keys:
            errors.append(f"Нет канала {k}")
    for name, blocks in list(POSTS.items()) + [(k, v[0]) for k, v in PANELS.items()] + \
            [("WELCOME_CITIZEN", TX.WELCOME_CITIZEN)]:
        total = 0
        for t, d in blocks:
            total += len(t) + len(d)
            if len(t) > 256 or len(d) > 4096:
                errors.append(f"{name}: блок «{t}» слишком длинный")
        if total > 6000 or len(blocks) > 10:
            errors.append(f"{name}: всего {total} символов / {len(blocks)} блоков (лимит 6000 / 10)")
    for kind, (title, fields) in TX.APPLY_FORMS.items():
        if len(fields) > 5:
            errors.append(f"Форма {kind}: больше 5 полей")
        for label, *_ in fields:
            if len(label) > 45:
                errors.append(f"Форма {kind}: подпись «{label}» длиннее 45")
        for f in C.FACTIONS:
            if len(f"{title}: {f['member']}") > 45 and kind in ("org", "lead"):
                pass  # обрезается автоматически
    for p in C.MAT_PATTERNS:
        re.compile(p)
    for spec in C.ROLES:
        for flag in spec["perms"]:
            if flag not in VALID:
                errors.append(f"Роль {spec['name']}: неизвестное право {flag}")
    return errors, len(C.ROLES), len(C.CATEGORIES), n_channels


def who(names):
    return "все" if C.EVERYONE in names else (", ".join(names) if names else "только бот")


def docs():
    out = ["# Структура Discord-сервера «СССР РП»", "",
           "Файл создан командой `python bot.py --docs` из `config.py` и `texts.py`.", "",
           "## Роли (сверху вниз)", "", "| Роль | Цвет | Права на сервере |", "|---|---|---|"]
    for r in C.ROLES:
        p = ", ".join(k for k, v in r["perms"].items() if v) or "—"
        out.append(f"| {r['name']} | `#{r['color']:06X}` | {p} |")
    out += ["", "Роль бота должна стоять **выше всех** — иначе он не сможет выдавать роли.", "",
            "## Категории и каналы", ""]
    for cat in C.CATEGORIES:
        view, send, manage, hidden, _ = channel_rules(cat)
        out.append(f"### {cat['name']}")
        out.append(f"Видят: {who(view)}" + (f" • пишут: {who(send)}" if set(send) != set(view) else "")
                   + (f" • управляют каналами: {who(manage)}" if manage else "")
                   + (f" • скрыто от: {who(hidden)}" if hidden else ""))
        out.append("")
        for ch in cat["channels"]:
            v, s, *_ = channel_rules(cat, ch)
            extra = []
            if "view" in ch:
                extra.append(f"видят: {who(v)}")
            if set(s) != set(v) and set(s) != set(send):
                extra.append(f"пишут: {who(s)}")
            elif set(s) != set(v) and "view" in ch:
                extra.append(f"пишут: {who(s)}")
            if ch.get("slowmode"):
                extra.append(f"медленный режим {ch['slowmode']} с")
            name = ch["name"] if ch["type"] == "voice" else f"#{ch['name']}"
            out.append(f"- **{name}** — {ch.get('topic', '') or 'голосовой'}" + (f" *({'; '.join(extra)})*" if extra else ""))
        if not cat["channels"]:
            out.append("- *(сюда бот создаёт закрытые каналы тикетов)*")
        out.append("")
    out += ["## Тексты", ""]
    for name, blocks in [("#правила-сервера", TX.RULES_SERVER), ("#правила-игры", TX.RULES_GAME),
                         ("#верификация", TX.VERIFY), ("#заявки-в-организации", TX.APPLY_ORG),
                         ("#баг-репорты", TX.BUGS), ("#жалобы-на-игроков", TX.COMPLAINTS),
                         ("#обжалование-наказаний", TX.APPEALS), ("#скачать-игру", TX.DOWNLOAD),
                         ("Приветствие нового гражданина (#общий-чат)", TX.WELCOME_CITIZEN)]:
        out.append(f"### {name}")
        for t, d in blocks:
            out += [f"**{t}**", "", d, ""]
    out += ["### Приветствие при входе (#верификация, удаляется через 10 минут)", "", TX.WELCOME_JOIN, ""]
    return "\n".join(out)


def main():
    if "--check" in sys.argv:
        errors, nr, nc, nch = check_config()
        print(f"Ролей: {nr}, категорий: {nc}, каналов: {nch}")
        print("\n".join("ОШИБКА: " + e for e in errors) or "Всё в порядке ✅")
        sys.exit(1 if errors else 0)
    if "--docs" in sys.argv:
        print(docs())
        return
    load_env()
    token, gid = os.environ.get("DISCORD_TOKEN"), os.environ.get("GUILD_ID")
    if not token or not gid:
        sys.exit("Укажите DISCORD_TOKEN и GUILD_ID в файле .env (пример — .env.example)")
    Bot(int(gid)).run(token)


if __name__ == "__main__":
    main()
