"""Структура Discord-сервера «СССР РП»: роли, категории, каналы, права.

Здесь можно переименовывать каналы, менять цвета и права, а потом
снова запускать /настроить-сервер: бот обновит то, что уже создано,
и создаст недостающее. Ключи (key) не меняйте — по ним бот находит
каналы, которые он уже создал.
"""

# ── Оформление ──────────────────────────────────────────────────────────
RED = 0xC8102E      # советский красный
GOLD = 0xD4AF37     # золото
DARK = 0x1B1B1B     # тёмный
GREEN = 0x2E7D32
FOOTER = "☭ СССР РП • Казань • Пятигорск • Бусаево"

# ── Основные роли ───────────────────────────────────────────────────────
FOUNDER = "Основатель"
HEAD_ADMIN = "Главный администратор"
ADMIN = "Администратор"
MOD = "Модератор"
DEV = "Разработчик / Тестер"
CITIZEN = "Гражданин"
NEWBIE = "Новичок"
MUTE = "Мут"
BOTS = "Боты"

EVERYONE = "@everyone"

# Уровень администрации: чем больше, тем старше.
STAFF_LEVEL = {MOD: 1, ADMIN: 2, HEAD_ADMIN: 3, FOUNDER: 4}
STAFF = [HEAD_ADMIN, ADMIN, MOD]          # видят закрытые разделы
ADMINS = [HEAD_ADMIN, ADMIN]              # пишут в информационные каналы

WARN_LIMIT = 3            # столько предупреждений = бан
WARN_BAN_DAYS = 3         # на столько дней
ONE_FACTION_ONLY = True   # игрок может состоять только в одной организации

# ── Организации ─────────────────────────────────────────────────────────
# kind: gov — государственная, opg — группировка.
# hr — канал, куда бот пишет о приёме/увольнении.
FACTIONS = [
    dict(key="mayor", kind="gov", city="Казань", member="Мэрия", leader="Лидер Мэрии",
         color=0xB8962E, leader_color=0xE0B84A, emoji="🏛"),
    dict(key="police_kzn", kind="gov", city="Казань", member="Главная милиция", leader="Лидер Милиции",
         color=0x3A78D8, leader_color=0x1F5FBF, emoji="🚔"),
    dict(key="police_pt", kind="gov", city="Пятигорск", member="Милиция Пятигорска",
         leader="Лидер Милиции Пятигорска", color=0x6E9BE6, leader_color=0x2C5AA8, emoji="🚔"),
    dict(key="hosp_kzn", kind="gov", city="Казань", member="Главная больница", leader="Главврач",
         color=0xE4ECEC, leader_color=0xFAFAFA, emoji="🏥"),
    dict(key="hosp_pt", kind="gov", city="Пятигорск", member="Больница Пятигорска",
         leader="Главврач Пятигорска", color=0xA8D5CB, leader_color=0xCFE8E2, emoji="🏥"),
    dict(key="fire", kind="gov", city="Бусаево", member="Пожарная часть", leader="Начальник Пожарной части",
         color=0xFF7A3D, leader_color=0xFF4500, emoji="🔥"),
    dict(key="kgb", kind="gov", city="Казань", member="КГБ", leader="Председатель КГБ",
         color=0x3F7D4E, leader_color=0x2E5E3A, emoji="🕵️"),
    dict(key="tyap", kind="opg", city="Пятигорск", member="ОПГ «Тяп-Ляп»", leader="Вор в законе «Тяп-Ляп»",
         color=0xA0632B, leader_color=0x8B4513, emoji="🔫"),
    dict(key="univ", kind="opg", city="Пятигорск", member="Универсамское ОПГ",
         leader="Вор в законе «Универсам»", color=0x78909C, leader_color=0x546E7A, emoji="🔫"),
    dict(key="sun", kind="opg", city="Казань", member="Солнечные ОПГ", leader="Вор в законе «Солнечные»",
         color=0xF7C948, leader_color=0xF4B400, emoji="🔫"),
    dict(key="kavkaz", kind="opg", city="Казань", member="Кавказское ОПГ", leader="Вор в законе «Кавказ»",
         color=0x8E2A2A, leader_color=0x6A1B1B, emoji="🔫"),
]
FACTION_BY_KEY = {f["key"]: f for f in FACTIONS}
GOV = [f for f in FACTIONS if f["kind"] == "gov"]
OPG = [f for f in FACTIONS if f["kind"] == "opg"]


def _f(key):
    return FACTION_BY_KEY[key]


# ── Роли сверху вниз ────────────────────────────────────────────────────
# perms — права на весь сервер. Видимость каналов настраивается ниже.
_HEAD_ADMIN_PERMS = dict(
    manage_guild=True, manage_roles=True, manage_channels=True, kick_members=True,
    ban_members=True, moderate_members=True, manage_messages=True, pin_messages=True,
    manage_nicknames=True, manage_threads=True, view_audit_log=True, mention_everyone=True,
    mute_members=True, deafen_members=True, move_members=True, manage_events=True,
    manage_expressions=True,
)
_ADMIN_PERMS = dict(
    manage_roles=True, kick_members=True, ban_members=True, moderate_members=True,
    manage_messages=True, pin_messages=True, manage_nicknames=True, manage_threads=True,
    view_audit_log=True, mute_members=True, move_members=True, manage_events=True,
)
_MOD_PERMS = dict(
    moderate_members=True, manage_messages=True, pin_messages=True, manage_threads=True,
    mute_members=True, move_members=True,
)

ROLES = [
    dict(name=FOUNDER, color=0xFFD700, hoist=True, perms=dict(administrator=True)),
    dict(name=HEAD_ADMIN, color=0xB71C1C, hoist=True, perms=_HEAD_ADMIN_PERMS),
    dict(name=ADMIN, color=0xE53935, hoist=True, perms=_ADMIN_PERMS),
    dict(name=MOD, color=0xFF8A65, hoist=True, perms=_MOD_PERMS),
    dict(name=DEV, color=0x9575CD, hoist=True, perms={}),
    *[dict(name=f["leader"], color=f["leader_color"], hoist=False, perms={}) for f in FACTIONS],
    *[dict(name=f["member"], color=f["color"], hoist=True, perms={}) for f in FACTIONS],
    dict(name=CITIZEN, color=0xCDB891, hoist=True, perms={}),
    dict(name=NEWBIE, color=0x95A5A6, hoist=False, perms={}),
    dict(name=MUTE, color=0x3B3B3B, hoist=False, perms={}),
    dict(name=BOTS, color=0x607D8B, hoist=True, perms={}),
]

# Права @everyone на весь сервер (что можно делать там, где канал виден).
EVERYONE_PERMS = dict(
    view_channel=True, read_message_history=True, send_messages=True,
    send_messages_in_threads=True, create_public_threads=False, create_private_threads=False,
    embed_links=True, attach_files=True, add_reactions=True, use_external_emojis=True,
    use_external_stickers=True, use_application_commands=True, connect=True, speak=True,
    stream=True, use_voice_activation=True, use_embedded_activities=True,
    change_nickname=False, create_instant_invite=True, mention_everyone=False,
)

# ── Каналы ──────────────────────────────────────────────────────────────
# Категория:  key, name, view (кто видит), send (кто пишет; по умолчанию = view),
#             manage (кто управляет каналами категории и закрепляет), hidden (кому скрыть).
# Канал:      key, name, type ("text" | "voice"), topic, те же view/send/manage/hidden
#             (если не указаны — берутся от категории), slowmode (сек),
#             post — какой текст или панель бот опубликует в канале.
# Роль «Боты» автоматически видит и пишет везде. «Мут» не может писать нигде.

def T(key, name, topic="", **kw):
    return dict(key=key, name=name, type="text", topic=topic, **kw)


def V(key, name, **kw):
    return dict(key=key, name=name, type="voice", **kw)


def _members(f):
    return [f["member"], f["leader"]]


def _faction_category(f, cat_name, channels):
    return dict(key=f["key"], name=cat_name, faction=f["key"],
                view=_members(f) + STAFF, manage=[f["leader"]], channels=channels)


def _leader_only(f):
    """Канал, который видит вся организация, а пишут лидер и администрация."""
    return [f["leader"]] + ADMINS


def _police(key, cat_name):
    f = _f(key)
    return _faction_category(f, cat_name, [
        T("charter", "📕・устав-милиции", "Устав милиции. Пишет лидер.", send=_leader_only(f), post="charter"),
        T("wanted", "🚔・ориентировки", "Кто в розыске: ник, приметы, за что, фото."),
        T("reports", "📝・рапорты", "Отчёты о задержаниях: кто задержал, кого, за что, время."),
        T("hr", "🗂・кадры", "Приём, увольнения, повышения.", send=_leader_only(f)),
        T("chat", "💬・чат-милиции", "Служебный чат."),
        V("voice", "🔊 Дежурная часть"),
    ])


def _hospital(key, cat_name):
    f = _f(key)
    return _faction_category(f, cat_name, [
        T("charter", "📗・устав-больницы", "Устав больницы. Пишет главврач.", send=_leader_only(f), post="charter"),
        T("calls", "🚑・вызовы", "Вызовы и отчёты о помощи."),
        T("hr", "🗂・кадры", "Приём, увольнения, повышения.", send=_leader_only(f)),
        T("chat", "💬・чат-врачей", "Служебный чат."),
        V("voice", "🔊 Ординаторская"),
    ])


def _opg(key, cat_name):
    f = _f(key)
    return _faction_category(f, cat_name, [
        T("rules", "📜・понятия", "Внутренние правила группировки. Пишет вор в законе.",
          send=_leader_only(f), post="charter"),
        T("bank", "💰・общак", "Взносы и отчёты."),
        T("chat", "🗣・сходка", "Чат группировки."),
        T("plans", "🎯・дела", "Планы: угоны, захваты, цеха."),
        T("hr", "👥・состав", "Кто в группировке и в каком ранге.", send=_leader_only(f), post="opg_ranks"),
        V("voice", "🔊 Гараж"),
    ])


_CITIZENS = [CITIZEN] + STAFF + [DEV]
_GOV_ALL = [r for f in GOV for r in _members(f)] + STAFF
_OPG_ALL = [r for f in OPG for r in _members(f)] + STAFF
_OPG_LEADERS = [f["leader"] for f in OPG] + ADMINS

CATEGORIES = [
    dict(key="info", name="📌 ИНФОРМАЦИЯ", view=[EVERYONE], send=ADMINS, channels=[
        T("rules_server", "📜・правила-сервера", "Правила Discord-сервера.", post="rules_server"),
        T("rules_game", "⚖️・правила-игры", "RP-правила игры.", post="rules_game"),
        T("news", "📰・новости", "Новости и обновления игры."),
        T("changelog", "📋・список-изменений", "Что изменилось в каждой версии."),
        T("download", "📲・скачать-игру", "Ссылка на APK и инструкция установки.", post="download"),
        T("events", "🎉・анонсы-событий", "События города, праздники, мероприятия."),
    ]),
    dict(key="verify", name="✅ ВЕРИФИКАЦИЯ", view=[EVERYONE] + STAFF, send=ADMINS, hidden=[CITIZEN], channels=[
        T("verify", "✅・верификация", "Укажи игровой ник и получи роль «Гражданин».", post="verify"),
    ]),
    dict(key="general", name="💬 ОБЩЕНИЕ", view=_CITIZENS, filtered=True, channels=[
        T("chat", "☭・общий-чат", "Общение граждан. Без мата и оскорблений."),
        T("flood", "🗯・флуд", "Флуд разрешён, мат и оскорбления — нет."),
        T("media", "📸・скриншоты-и-видео", "Скриншоты и видео из игры."),
        T("lfg", "🔎・поиск-игроков", "Ищешь напарника, семью или организацию — пиши сюда."),
        T("ideas", "💡・предложения", "Одна идея — одно сообщение. Голосуйте 👍/👎.",
          slowmode=120, post="ideas"),
        V("v_general", "🔊 Общий"),
        V("v_kazan", "🔊 Казань"),
        V("v_pyatigorsk", "🔊 Пятигорск"),
        V("v_busaevo", "🔊 Бусаево"),
    ]),
    dict(key="support", name="🆘 ПОДДЕРЖКА", view=_CITIZENS, filtered=True, channels=[
        T("tickets", "🎫・создать-тикет", "Личное обращение к администрации.", send=ADMINS, post="tickets"),
        T("bugs", "🐞・баг-репорты", "Только по шаблону из закрепа.", slowmode=60, post="bugs"),
        T("complaints", "🚨・жалобы-на-игроков", "Только по шаблону из закрепа.", slowmode=60,
          post="complaints"),
        T("admin_complaints", "🔒・жалобы-на-администрацию",
          "Видят только Главный администратор и Основатель. Жалобы подаются через тикет.",
          view=[HEAD_ADMIN], send=[HEAD_ADMIN]),
        T("questions", "❓・вопросы-к-администрации", "Вопросы по игре и серверу."),
        T("appeals", "⚖️・обжалование-наказаний", "Только по шаблону из закрепа.", slowmode=60,
          post="appeals"),
    ]),
    dict(key="tickets", name="🎫 ТИКЕТЫ", view=[], channels=[]),

    # ── Государственные организации ──
    dict(**_faction_category(_f("mayor"), "🏛 МЭРИЯ КАЗАНИ", [
        T("announce", "📢・объявления-мэрии", "Официальные объявления мэрии.", send=_leader_only(_f("mayor"))),
        T("chat", "💬・чат-мэрии", "Служебный чат."),
        T("hr", "🗂・кадры", "Приём, увольнения, повышения.", send=_leader_only(_f("mayor"))),
        T("reception", "🏛・приём-граждан", "Обращения граждан к мэрии. Видят все.",
          view=_members(_f("mayor")) + _CITIZENS, slowmode=60),
        V("voice", "🔊 Мэрия"),
    ])),
    _police("police_kzn", "🚔 ГЛАВНАЯ МИЛИЦИЯ"),
    _police("police_pt", "🚔 МИЛИЦИЯ ПЯТИГОРСКА"),
    _hospital("hosp_kzn", "🏥 ГЛАВНАЯ БОЛЬНИЦА"),
    _hospital("hosp_pt", "🏥 БОЛЬНИЦА ПЯТИГОРСКА"),
    dict(**_faction_category(_f("fire"), "🔥 ПОЖАРНАЯ ЧАСТЬ БУСАЕВО", [
        T("charter", "📙・устав-пожарных", "Устав пожарной части.", send=_leader_only(_f("fire")), post="charter"),
        T("trips", "🔥・выезды", "Отчёты о тушении: где, когда, кто выезжал."),
        T("hr", "🗂・кадры", "Приём, увольнения, повышения.", send=_leader_only(_f("fire"))),
        T("chat", "💬・чат-части", "Служебный чат."),
        V("voice", "🔊 Диспетчерская"),
    ])),
    dict(**_faction_category(_f("kgb"), "🕵️ КГБ", [
        T("charter", "📘・устав-кгб", "Устав КГБ.", send=_leader_only(_f("kgb")), post="charter"),
        T("ops", "🕵️・оперативные-данные", "Только КГБ и администрация.",
          view=_members(_f("kgb")) + ADMINS),
        T("dossier", "🗃・досье", "Досье на подозреваемых."),
        T("hr", "🗂・кадры", "Приём, увольнения, повышения.", send=_leader_only(_f("kgb"))),
        T("chat", "💬・чат-кгб", "Служебный чат."),
        V("voice", "🔊 Совещание"),
    ])),
    dict(key="gov_common", name="📻 ГОССЛУЖБЫ", view=_GOV_ALL, channels=[
        T("radio", "📻・рация-госслужб", "Совместные операции и вызовы милиции."),
    ]),

    # ── ОПГ ──
    _opg("tyap", "🔫 ОПГ «ТЯП-ЛЯП» • ПЯТИГОРСК"),
    _opg("univ", "🔫 УНИВЕРСАМСКОЕ ОПГ • ПЯТИГОРСК"),
    _opg("sun", "🔫 СОЛНЕЧНЫЕ ОПГ • КАЗАНЬ"),
    _opg("kavkaz", "🔫 КАВКАЗСКОЕ ОПГ • КАЗАНЬ"),
    dict(key="opg_common", name="🔫 ОПГ: ОБЩЕЕ", view=_OPG_ALL, channels=[
        T("arrows", "🤝・стрелки", "Договорённости и конфликты между группировками."),
        T("territory", "🗺・территории", "Кто какой район держит. Пишут воры в законе.",
          send=_OPG_LEADERS, post="territory"),
    ]),

    # ── Заявки ──
    dict(key="apps", name="📝 ЗАЯВКИ", view=_CITIZENS, send=ADMINS, filtered=True, channels=[
        T("org", "📝・заявки-в-организации", "Заявки подаются кнопкой ниже.", post="apply_org"),
        T("lead", "⭐・заявки-на-лидерство", "Видит только администрация.", view=STAFF),
        T("admin", "🛡・заявки-в-администрацию", "Набор модераторов.", post="apply_admin"),
        T("tester", "🧪・набор-тестеров", "Набор тестеров.", post="apply_tester"),
    ]),

    # ── Тестирование (для роли «Разработчик / Тестер») ──
    dict(key="testing", name="🧪 ТЕСТИРОВАНИЕ", view=[DEV] + ADMINS, channels=[
        T("builds", "📦・тестовые-сборки", "Тестовые APK.", send=[DEV] + ADMINS),
        T("bugs", "🐞・баги-тестеров", "Баги тестовых сборок."),
        T("chat", "💬・чат-тестеров", "Обсуждение."),
        V("voice", "🔊 Тестирование"),
    ]),

    # ── Администрация ──
    dict(key="admin", name="🛡 АДМИНИСТРАЦИЯ", view=STAFF, channels=[
        T("chat", "💬・админ-чат", "Чат администрации."),
        T("punish_log", "📕・логи-наказаний", "Кто, кого, за что, на сколько. Пишет бот.", send=[]),
        T("check", "🔍・проверка-жалоб", "Разбор жалоб."),
        T("leaders", "📋・список-лидеров", "Актуальные лидеры организаций.", send=ADMINS),
        T("important", "❗・важное-для-админов", "Важное. Пишет Главный администратор.", send=[HEAD_ADMIN]),
        V("voice", "🔊 Совещание администрации"),
    ]),

    # ── Боты ──
    dict(key="bots", name="🤖 БОТЫ", view=_CITIZENS, channels=[
        T("server_log", "📜・логи-сервера", "Вход/выход, удаления, смена ролей.", view=STAFF, send=[]),
        T("commands", "🤖・команды-ботов", "Команды ботов."),
    ]),
]

# Куда бот пишет. Формат: "категория.канал".
CH_SERVER_LOG = "bots.server_log"
CH_PUNISH_LOG = "admin.punish_log"
CH_VERIFY = "verify.verify"
CH_WELCOME = "general.chat"
CH_IDEAS = "general.ideas"
CH_ADMIN_COMPLAINTS = "support.admin_complaints"
CH_APPLY = {"org": "apps.org", "lead": "apps.lead", "admin": "apps.admin", "tester": "apps.tester"}
TICKET_CATEGORY = "tickets"

# ── Тикеты ──────────────────────────────────────────────────────────────
TICKET_TYPES = [
    dict(key="complaint", label="Жалоба на игрока", emoji="🚨", staff=STAFF),
    dict(key="bug", label="Баг", emoji="🐞", staff=STAFF + [DEV]),
    dict(key="question", label="Вопрос", emoji="❓", staff=STAFF),
    dict(key="application", label="Заявка", emoji="📝", staff=STAFF),
    dict(key="admin", label="Жалоба на администрацию", emoji="🔒", staff=[HEAD_ADMIN]),
]
TICKET_TYPE_BY_KEY = {t["key"]: t for t in TICKET_TYPES}
MAX_OPEN_TICKETS = 2

# ── Автомодерация ───────────────────────────────────────────────────────
# Мат и капс бот удаляет в категориях с filtered=True (общие каналы).
CAPS_MIN_LETTERS = 12
CAPS_RATIO = 0.7
_L = r"(?<![а-яa-z])"   # начало слова
MAT_PATTERNS = [
    _L + r"(?:по|на|о|за|от|ни|охуе|ахуе)?ху[йеёяюи]",
    r"пизд",
    _L + r"(?:за|вы|на|по|от|у|до|при|про|раз|съ|из|въ|о|подъ|объ)?[её]б(?:а|у|ал|ан|ат|л|н|ну|ыв|ись|ет|ёт|и|ук|ок)",
    _L + r"бл[яэ](?:д|т|ть)?",
    _L + r"муд[аои]",
    r"п[иеё]д[оа]р",
    _L + r"сук[аиуе]",
    r"г[ао]нд[оа]н",
    r"залуп",
    r"шлюх",
]
# Приглашения на чужие серверы — блокирует встроенная автомодерация Discord.
INVITE_REGEX = r"(?:discord(?:app)?\.com/invite|discord\.(?:gg|io|me|li))/\S+"
MENTION_LIMIT = 5
