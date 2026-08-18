local M = {}

local lastMenu       = -1
local lastSubmenu    = -1
local lastParkingSensors = -1
local lastSideAssist     = -1
local lastAmbientLights  = -1
local lastRearSeatHeating = -1

local lastIgnition   = 0
local savedMenu      = 0
local savedSubmenu   = 0
local savedBgLighting = nil
local dialTimer      = 0
local endCallTimer   = 0
local wiperServiceTarget = 0
local wiperServiceStart  = 0
local wiperServicePeriod = 0
local wiperServiceActive = false
local WIPER_SERVICE_SPEED = 5  -- same rate as front wipers

-- Climate corner button state (Setup AC → Blower / Distribution / Seat heat.)
local climateCornerCtx  = 0    -- which HVAC context was opened by a corner button (0 = none)
local prevRawSubmenu    = 0    -- previous frame's raw submenu (for corner press detection)

local SCREEN = {
    NAV         = 1,
    MEDIA       = 2,
    CLIMATE     = 4,
    CAR         = 5,
    NAME        = 6,
    TEL         = 7,
    PARKING     = 100,
    REVERSE_CAM = 101,
}

local climateWasActive     = false
local reverseShowCamera    = nil
local lastReverseCamToggle = nil
local lastReverse          = false
local parkingShowSettings    = false
local parkingCamDefaultDone  = false  -- one-shot: camera-equipped cars default to the camera view

-- Menu button re-press detection: maps electrics toggle values to menu IDs
local MENU_BUTTONS = {
    mmi_nav  = 1,
    mmi_cd   = 2,
    mmi_car  = 5,
    mmi_name = 6,
    mmi_tel  = 7,
}
local prevMenuButtons = {}

-- Navigation stack: replaces carSystemsScroll, parkingSettingsScroll, soundSettingsScroll, lastDetailView, lastClimateDetailView
local dvStack = {}

local function loadMedia()
    local f = io.open("/settings/audi6/media.json", "r")
    if not f then return {}, {} end
    local raw  = f:read("*a")
    f:close()
    local data = jsonDecode(raw)
    if type(data) ~= "table" then return {}, {} end
    local sources = data.sources or {}
    local changer = {}
    for i = 1, #sources do changer[i] = "CD" .. i end
    return changer, sources
end

local DEFAULT_CONTACTS = {
    male    = {"Bates, Peter", "Green, Andrew", "Williams, David"},
    female  = {"Anna, Harris", "Blake, Mary"},
    service = {"AUDISERVICE"},
}

local DEFAULT_MEDIA = {
    sources = {"BT Audio", "On-The-Go 1", "Recently Added", "Recently Played", "Mark.s iPod", "Menu"},
}

local function ensureDefaultFiles()
    local contactsPath = "/settings/audi6/contacts.json"
    local mediaPath    = "/settings/audi6/media.json"

    local fc = io.open(contactsPath, "r")
    if not fc then
        jsonWriteFile(contactsPath, DEFAULT_CONTACTS, true)
    else
        fc:close()
    end

    local fm = io.open(mediaPath, "r")
    if not fm then
        jsonWriteFile(mediaPath, DEFAULT_MEDIA, true)
    else
        fm:close()
    end
end

local function loadContacts()
    local f = io.open("/settings/audi6/contacts.json", "r")
    if not f then return {}, {}, {} end
    local raw  = f:read("*a")
    f:close()
    local data = jsonDecode(raw)
    if type(data) ~= "table" then return {}, {}, {} end
    return data.male or {}, data.female or {}, data.service or {}
end

local _changer, _sources = loadMedia()
local _changerList = {}
for i, c in ipairs(_changer) do _changerList[i] = c .. ' - ' .. (_sources[i] or '') end

local CAR_SUSPENSION_AIR   = {'lift', 'comfort', 'automatic', 'dynamic'}
local CAR_SUSPENSION_SPORT = {'comfort', 'dynamic', 'sport'}

local MENU_ITEMS = {
    MEDIA_CHANGER = _changerList,
    MEDIA_SOURCE   = {'CD', 'TV', 'External AV source1', 'External AV source2', 'AUX'},
    MEDIA_CONTROL  = {'Forward', 'Reverse', 'Next', 'Previous', 'Shuffle', 'SCAN'},
    MEDIA_SOUND    = {'Balance', 'Fader', 'Treble', 'Bass', 'Volume settings'},
    DSP_BOSE       = {'Sound focus', 'AudioPilot™'},
    VOLUME_SETTINGS = {'Traffic report', 'Voice guidance', 'Audio during route guid.', 'Speech dialogue system', 'Telephone volume'},
    CAR_SYSTEMS    = {'Battery level',
                      'Central locking', 
                      'Exterior lighting',
                      'Seat adjustment',
                      'Service interval display', 
                      'Tire pressure monitoring',
                      'Vehicle ID Number', 
                      'Windows', 
                      'Windshield wipers'},
    CAR_SUSPENSION = CAR_SUSPENSION_AIR,
    CAR_CENTRAL_LOCKING = {'Passenger.s door', 'Left rear door', 'Right rear door', 'Boot lid/tailgate', 'Auto locking'},
	CAR_EXT_LIGHTING = {'coming home', 'leaving home', 'DRLs'},
    CAR_WIPERS = {'Service position'},
    PARKING_SETTINGS = {'Display', 'Front volume', 'Front frequency', 'Rear volume', 'Rear frequency'},
    CLIMATE        = {'Econ', 'Auto recirc.', 'Synchron.', 'Centre air vent'},
    NAME_EDIT      = {'New entry', 'Change entry', 'Copy entry', 'Delete entry', 'Memory capacity'},
    NAME_CALL      = {'Call', 'Start route guidance to'},
}


-- Translation is static for the current vehicle session.
-- Set electrics.values.translateLanguage before init/reset.
-- Supported: 0 = English (US, default), 1 = British English, 2 = German, 3 = Polish, 4 = Japanese.
-- American English is the default and is not counted as a translation.
local activeLanguage = 'en'

local TRANSLATIONS = {
    ja = {
        -- Media / audio. Short, MMI-style labels.
        ['BT Audio'] = 'Bluetoothオーディオ',
        ['On-The-Go 1'] = 'On-The-Go 1',
        ['Recently Added'] = '最近追加した曲',
        ['Recently Played'] = '最近再生した曲',
        ['Mark.s iPod'] = 'MarkのiPod',
        ['Menu'] = 'メニュー',

        ['TV'] = 'TV',
        ['External AV source1'] = '外部AV入力1',
        ['External AV source2'] = '外部AV入力2',
        ['AUX'] = 'AUX',
        ['Forward'] = '早送り',
        ['Reverse'] = '早戻し',
        ['Next'] = '次の曲',
        ['Previous'] = '前の曲',
        ['Shuffle'] = 'ランダム再生',
        ['SCAN'] = 'スキャン',
        ['Balance'] = 'バランス',
        ['Fader'] = 'フェーダー',
        ['Treble'] = '高音',
        ['Bass'] = '低音',
        ['Volume settings'] = '音量設定',
        ['left'] = '左',
        ['right'] = '右',
        ['rear'] = '後',
        ['front'] = '前',
        ['DSP BOSE'] = 'DSP BOSE',
        ['Sound focus'] = 'サウンドフォーカス',
        ['AudioPilot™'] = 'AudioPilot™',
        ['Driver'] = 'ドライバー',
        ['Traffic report'] = '交通情報',
        ['Voice guidance'] = '音声案内',
        ['Audio during route guid.'] = 'ルート案内中の音声',
        ['Speech dialogue system'] = '音声対話システム',
        ['Telephone volume'] = '電話音量',

        -- Suspension drive modes.
        ['lift'] = 'リフト',
        ['comfort'] = 'コンフォート',
        ['automatic'] = 'オート',
        ['dynamic'] = 'ダイナミック',
        ['sport'] = 'スポーツ',

        -- Car systems.
        ['Audi parking system'] = 'Audiパーキングシステム',
        ['Audi side assist'] = 'Audiサイドアシスト',
        ['Background lighting'] = 'アンビエントライト',
        ['Battery level'] = 'バッテリー残量',
        ['Central locking'] = '集中ドアロック',
        ['Exterior lighting'] = 'エクステリアライト',
        ['Seat adjustment'] = 'シート調整',
        ['Service interval display'] = 'サービスインターバル表示',
        ['Tire pressure monitoring'] = 'タイヤ空気圧モニター',
        ['Vehicle ID Number'] = '車台番号',
        ['Windows'] = 'ウインドウ',
        ['Windshield wipers'] = 'ワイパー',
        ['Passenger.s door'] = '助手席ドア',
        ['Left rear door'] = '左リアドア',
        ['Right rear door'] = '右リアドア',
        ['Boot lid/tailgate'] = 'トランクリッド',
        ['Auto locking'] = 'オートロック',
        ['Service position'] = 'サービスポジション',
        ['Display'] = '表示',
        ['Front volume'] = '前方音量',
        ['Front frequency'] = '前方周波数',
        ['Rear volume'] = '後方音量',
        ['Rear frequency'] = '後方周波数',

        -- Climate.
        ['Econ'] = 'エコノミー',
        ['Auto recirc.'] = '自動内気循環',
        ['Synchron.'] = 'シンクロ',
        ['Centre air vent'] = 'センター吹出口',
        ['Aux. heating'] = '補助ヒーター',
        ['Aux. vent'] = '補助換気',
		
		['cooler'] = '冷',
		['warmer'] = '暖',

        -- Directory / telephone menu items.
        ['New entry'] = '新規登録',
        ['Change entry'] = '登録変更',
        ['Copy entry'] = '登録コピー',
        ['Delete entry'] = '登録削除',
        ['Memory capacity'] = 'メモリー容量',
        ['Call'] = '発信',
        ['Start route guidance to'] = 'ルート案内開始',

        -- General screen labels used by the JS variants.
        ['Navigation'] = 'ナビゲーション',
        ['Note'] = 'お知らせ',
        ['Navigation is not installed.'] = 'ナビゲーションは装備されていません',
        ['Nav-Info'] = 'ナビ情報',
        ['Destination'] = '目的地',
        ['Changer'] = 'チェンジャー',
        ['Source'] = 'ソース',
        ['CD control'] = 'CD操作',
        ['Sound'] = 'サウンド',
        ['Passenger'] = '助手席',
        ['Driver'] = '運転席',
        ['Setup AC'] = 'エアコン設定',
        ['Seat heat.'] = 'シートヒーター',
        ['Blower'] = '風量',
        ['Distribution'] = '吹出口',
        ['auto'] = 'オート',
        ['on'] = 'オン',
        ['off'] = 'オフ',
        ['Car'] = '車両',
        ['Version'] = 'バージョン',
        ['Systems'] = 'システム',
        ['Version information'] = 'バージョン情報',
        ['Software version:'] = 'ソフトウェアバージョン:',
        ['Nav. database version:'] = 'ナビデータベース:',
        ['The required data for'] = '必要なデータが',
        ['the service interval display'] = 'サービスインターバル表示に',
        ['are not yet available.'] = 'まだありません',
        ['sports suspension plus'] = 'スポーツサスペンションプラス',
        ['adaptive air suspension'] = 'アダプティブエアサスペンション',
        ['Telephone'] = '電話',
        ['Telephone is not installed.'] = '電話は装備されていません',
        ['Directory'] = '電話帳',
        ['Import'] = 'インポート',
        ['Edit'] = '編集',
        ['Options'] = 'オプション',
        ['Find entry'] = '連絡先検索',
        ['Import all entries'] = '全件インポート',
        ['From phone book'] = '電話帳から',
        ['Telephone - T-Mobile'] = '電話 - T-Mobile',
        ['Memory'] = 'メモリー',
        ['Dial'] = '発信',
        ['End call'] = '終了',
        ['Phone book'] = '電話帳',
        ['Connected'] = '通話中',
        ['Dialing'] = '発信中',
        ['Look! Safe to move?'] = '周囲を確認してください',
        ['Settings'] = '設定',
        ['Graphic'] = 'グラフィック',
        ['Rear View'] = '後方表示',
        ['Set'] = '設定',
        ['Unknown'] = '不明',
        ['dark'] = '暗い',
        ['bright'] = '明るい',
    },

    de = {
        -- Media / audio. Audi/VW-style German labels.
        ['BT Audio'] = 'BT-Audio',
        ['On-The-Go 1'] = 'On-The-Go 1',
        ['Recently Added'] = 'Zuletzt hinzugefügt',
        ['Recently Played'] = 'Zuletzt gespielt',
        ['Mark.s iPod'] = 'Marks iPod',
        ['Menu'] = 'Menü',

        ['TV'] = 'TV',
        ['External AV source1'] = 'Externe AV-Quelle 1',
        ['External AV source2'] = 'Externe AV-Quelle 2',
        ['AUX'] = 'AUX',
        ['Forward'] = 'Vorwärts',
        ['Reverse'] = 'Rückwärts',
        ['Next'] = 'Nächster Titel',
        ['Previous'] = 'Vorheriger Titel',
        ['Shuffle'] = 'Zufallswiedergabe',
        ['SCAN'] = 'SCAN',
        ['Balance'] = 'Balance',
        ['Fader'] = 'Fader',
        ['Treble'] = 'Höhen',
        ['Bass'] = 'Bass',
        ['Volume settings'] = 'Lautstärkeeinstellungen',
        ['left'] = 'links',
        ['right'] = 'rechts',
        ['rear'] = 'hinten',
        ['front'] = 'vorne',
        ['DSP BOSE'] = 'DSP BOSE',
        ['Sound focus'] = 'Klangfokus',
        ['AudioPilot™'] = 'AudioPilot™',
        ['Driver'] = 'Fahrer',
        ['Traffic report'] = 'Verkehrsmeldung',
        ['Voice guidance'] = 'Sprachführung',
        ['Audio during route guid.'] = 'Audio bei Routenführung',
        ['Speech dialogue system'] = 'Sprachdialogsystem',
        ['Telephone volume'] = 'Telefonlautstärke',

        -- Suspension drive modes.
        ['lift'] = 'lift',
        ['comfort'] = 'comfort',
        ['automatic'] = 'automatic',
        ['dynamic'] = 'dynamic',
        ['sport'] = 'sport',

        -- Car systems.
        ['Audi parking system'] = 'Audi parking system',
        ['Audi side assist'] = 'Audi side assist',
        ['Background lighting'] = 'Ambiente-Beleuchtung',
        ['Battery level'] = 'Batterieladezustand',
        ['Central locking'] = 'Zentralverriegelung',
        ['Exterior lighting'] = 'Außenbeleuchtung',
        ['Seat adjustment'] = 'Sitzeinstellung',
        ['Service interval display'] = 'Service-Intervallanzeige',
        ['Tire pressure monitoring'] = 'Reifendruck-Kontrolle',
        ['Vehicle ID Number'] = 'Fahrgestellnummer',
        ['Windows'] = 'Fenster',
        ['Windshield wipers'] = 'Scheibenwischer',
        ['Passenger.s door'] = 'Beifahrertür',
        ['Left rear door'] = 'Tür hinten links',
        ['Right rear door'] = 'Tür hinten rechts',
        ['Boot lid/tailgate'] = 'Heckklappe',
        ['Auto locking'] = 'Autom. Verriegelung',
        ['Service position'] = 'Servicestellung',
        ['Display'] = 'Anzeige',
        ['Front volume'] = 'Vorne Lautstärke',
        ['Front frequency'] = 'Vorne Frequenz',
        ['Rear volume'] = 'Hinten Lautstärke',
        ['Rear frequency'] = 'Hinten Frequenz',

        -- Climate.
        ['Econ'] = 'Econ',
        ['Auto recirc.'] = 'Autom. Umluft',
        ['Synchron.'] = 'Synchron.',
        ['Centre air vent'] = 'Mittenausströmer',
        ['Aux. heating'] = 'Standheizung',
        ['Aux. vent'] = 'Standlüftung',
		
		['cooler'] = 'kühler',
		['warmer'] = 'wärmer',

        -- Directory / telephone menu items.
        ['New entry'] = 'Neuer Eintrag',
        ['Change entry'] = 'Eintrag ändern',
        ['Copy entry'] = 'Eintrag kopieren',
        ['Delete entry'] = 'Eintrag löschen',
        ['Memory capacity'] = 'Speicherkapazität',
        ['Call'] = 'Anrufen',
        ['Start route guidance to'] = 'Zielführung starten',

        -- General screen labels used by the JS variants.
        ['Navigation'] = 'Navigation',
        ['Note'] = 'Hinweis',
        ['Navigation is not installed.'] = 'Navigation ist nicht installiert.',
        ['Nav-Info'] = 'Nav-Info',
        ['Destination'] = 'Ziel',
        ['Changer'] = 'Wechsler',
        ['Source'] = 'Quelle',
        ['CD control'] = 'CD-Steuerung',
        ['Sound'] = 'Klang',
        ['Passenger'] = 'Beifahrer',
        ['Driver'] = 'Fahrer',
        ['Setup AC'] = 'Klima-Setup',
        ['Seat heat.'] = 'Sitzheizung',
        ['Blower'] = 'Gebläse',
        ['Distribution'] = 'Luftverteilung',
        ['auto'] = 'auto',
        ['on'] = 'ein',
        ['off'] = 'aus',
        ['Car'] = 'Car',
        ['Version'] = 'Version',
        ['Systems'] = 'Systeme',
        ['Version information'] = 'Versionsinformation',
        ['Software version:'] = 'Software-Version:',
        ['Nav. database version:'] = 'Nav.-Datenbankversion:',
        ['The required data for'] = 'Die erforderlichen Daten für',
        ['the service interval display'] = 'die Service-Intervallanzeige',
        ['are not yet available.'] = 'sind noch nicht verfügbar.',
        ['sports suspension plus'] = 'sports suspension plus',
        ['adaptive air suspension'] = 'adaptive air suspension',
        ['Telephone'] = 'Telefon',
        ['Telephone is not installed.'] = 'Telefon ist nicht installiert.',
        ['Directory'] = 'Adressbuch',
        ['Import'] = 'Importieren',
        ['Edit'] = 'Bearbeiten',
        ['Options'] = 'Optionen',
        ['Find entry'] = 'Eintrag suchen',
        ['Import all entries'] = 'Alle Einträge importieren',
        ['From phone book'] = 'Aus Telefonbuch',
        ['Telephone - T-Mobile'] = 'Telefon - T-Mobile',
        ['Memory'] = 'Speicher',
        ['Dial'] = 'Wählen',
        ['End call'] = 'Beenden',
        ['Phone book'] = 'Telefonbuch',
        ['Connected'] = 'Verbunden',
        ['Dialing'] = 'Wählen',
        ['Look! Safe to move?'] = 'Umfeld beachten!',
        ['Settings'] = 'Einstellungen',
        ['Graphic'] = 'Grafik',
        ['Rear View'] = 'Rückansicht',
        ['Set'] = 'Einstellen',
        ['Unknown'] = 'Unbekannt',
        ['dark'] = 'dunkel',
        ['bright'] = 'hell',
    },

    en_gb = {
        -- British English: only entries that differ from American English (the default).
        -- Sourced from the UK-market Audi A6 (C6) quick reference guide and owner's manual.
        -- All other strings fall through to the American English originals.

        -- Car systems (as shown in UK MMI CAR > Systems menu).
        ['Tire pressure monitoring'] = 'Tyre pressure monitoring',
        ['Windshield wipers'] = 'Windscreen wipers',
        ['Vehicle ID Number'] = 'Vehicle ident. number',
        ['Central locking'] = 'Central locking system',
        ['Background lighting'] = 'Ambient lighting',

        -- General screen labels.
        ['Dialing'] = 'Dialling',
    },

    pl = {
        -- Media / audio.
        ['BT Audio'] = 'BT Audio',
        ['On-The-Go 1'] = 'On-The-Go 1',
        ['Recently Added'] = 'Ostatnio dodane',
        ['Recently Played'] = 'Ostatnio odtwarzane',
        ['Mark.s iPod'] = 'iPod Marka',
        ['Menu'] = 'Menu',

        ['TV'] = 'TV',
        ['External AV source1'] = 'Zewn. źródło AV 1',
        ['External AV source2'] = 'Zewn. źródło AV 2',
        ['AUX'] = 'AUX',
        ['Forward'] = 'Do przodu',
        ['Reverse'] = 'Do tyłu',
        ['Next'] = 'Następny',
        ['Previous'] = 'Poprzedni',
        ['Shuffle'] = 'Losowo',
        ['SCAN'] = 'SCAN',
        ['Balance'] = 'Balans',
        ['Fader'] = 'Fader',
        ['Treble'] = 'Tony wysokie',
        ['Bass'] = 'Tony niskie',
        ['Volume settings'] = 'Ustawienia głośności',
        ['left'] = 'lewo',
        ['right'] = 'prawo',
        ['rear'] = 'tył',
        ['front'] = 'przód',
        ['DSP BOSE'] = 'DSP BOSE',
        ['Sound focus'] = 'Fokus dźwięku',
        ['AudioPilot™'] = 'AudioPilot™',
        ['Driver'] = 'Kierowca',
        ['Traffic report'] = 'Komunikaty drogowe',
        ['Voice guidance'] = 'Prowadzenie głosowe',
        ['Audio during route guid.'] = 'Dźwięk podczas nawig.',
        ['Speech dialogue system'] = 'System dialogu głosowego',
        ['Telephone volume'] = 'Głośność telefonu',

        -- Suspension drive modes.
        ['lift'] = 'podniesione',
        ['comfort'] = 'komfort',
        ['automatic'] = 'automatyczny',
        ['dynamic'] = 'dynamiczny',
        ['sport'] = 'sport',

        -- Car systems.
        ['Audi parking system'] = 'Audi system parkowania',
        ['Audi side assist'] = 'Audi side assist',
        ['Background lighting'] = 'Oświetlenie ambientowe',
        ['Battery level'] = 'Poziom naładowania',
        ['Central locking'] = 'Zamek centralny',
        ['Exterior lighting'] = 'Oświetlenie zewnętrzne',
        ['Seat adjustment'] = 'Regulacja fotela',
        ['Service interval display'] = 'Wskaźnik interw. serwisowego',
        ['Tire pressure monitoring'] = 'Kontrola ciśnienia opon',
        ['Vehicle ID Number'] = 'Numer identyf. pojazdu',
        ['Windows'] = 'Szyby',
        ['Windshield wipers'] = 'Wycieraczki',
        ['Passenger.s door'] = 'Drzwi pasażera',
        ['Left rear door'] = 'Lewe tylne drzwi',
        ['Right rear door'] = 'Prawe tylne drzwi',
        ['Boot lid/tailgate'] = 'Pokrywa bagażnika',
        ['Auto locking'] = 'Autom. blokowanie',
        ['Service position'] = 'Pozycja serwisowa',
        ['Display'] = 'Wyświetlacz',
        ['Front volume'] = 'Głośność przód',
        ['Front frequency'] = 'Częstotliwość przód',
        ['Rear volume'] = 'Głośność tył',
        ['Rear frequency'] = 'Częstotliwość tył',

        -- Climate.
        ['Econ'] = 'Econ',
        ['Auto recirc.'] = 'Autom. obieg',
        ['Synchron.'] = 'Synchron.',
        ['Centre air vent'] = 'Nawiew centralny',
        ['Aux. heating'] = 'Ogrzewanie post.',
        ['Aux. vent'] = 'Wentylacja post.',

        ['cooler'] = 'chłodniej',
        ['warmer'] = 'cieplej',

        -- Directory / telephone menu items.
        ['New entry'] = 'Nowy wpis',
        ['Change entry'] = 'Zmień wpis',
        ['Copy entry'] = 'Kopiuj wpis',
        ['Delete entry'] = 'Usuń wpis',
        ['Memory capacity'] = 'Pojemność pamięci',
        ['Call'] = 'Połączenie',
        ['Start route guidance to'] = 'Rozpocznij nawig. do',

        -- General screen labels used by the JS variants.
        ['Navigation'] = 'Nawigacja',
        ['Note'] = 'Uwaga',
        ['Navigation is not installed.'] = 'Nawigacja nie jest zainstalowana.',
        ['Nav-Info'] = 'Info nawig.',
        ['Destination'] = 'Cel',
        ['Changer'] = 'Zmieniarka',
        ['Source'] = 'Źródło',
        ['CD control'] = 'Sterowanie CD',
        ['Sound'] = 'Dźwięk',
        ['Passenger'] = 'Pasażer',
        ['Setup AC'] = 'Ustawienia klimat.',
        ['Seat heat.'] = 'Ogrzew. fotela',
        ['Blower'] = 'Nawiew',
        ['Distribution'] = 'Dystrybucja',
        ['auto'] = 'auto',
        ['on'] = 'wł.',
        ['off'] = 'wył.',
        ['Car'] = 'Pojazd',
        ['Version'] = 'Wersja',
        ['Systems'] = 'Systemy',
        ['Version information'] = 'Informacja o wersji',
        ['Software version:'] = 'Wersja oprogramowania:',
        ['Nav. database version:'] = 'Wersja bazy nawig.:',
        ['The required data for'] = 'Wymagane dane dla',
        ['the service interval display'] = 'wskaźnika interw. serwisowego',
        ['are not yet available.'] = 'nie są jeszcze dostępne.',
        ['sports suspension plus'] = 'sports suspension plus',
        ['adaptive air suspension'] = 'adaptive air suspension',
        ['Telephone'] = 'Telefon',
        ['Telephone is not installed.'] = 'Telefon nie jest zainstalowany.',
        ['Directory'] = 'Katalog',
        ['Import'] = 'Importuj',
        ['Edit'] = 'Edytuj',
        ['Options'] = 'Opcje',
        ['Find entry'] = 'Znajdź wpis',
        ['Import all entries'] = 'Importuj wszystkie wpisy',
        ['From phone book'] = 'Z książki telefonicznej',
        ['Telephone - T-Mobile'] = 'Telefon - T-Mobile',
        ['Memory'] = 'Pamięć',
        ['Dial'] = 'Wybierz',
        ['End call'] = 'Zakończ',
        ['Phone book'] = 'Książka telefoniczna',
        ['Connected'] = 'Połączono',
        ['Dialing'] = 'Wybieranie',
        ['Look! Safe to move?'] = 'Uwaga! Czy można jechać?',
        ['Settings'] = 'Ustawienia',
        ['Graphic'] = 'Grafika',
        ['Rear View'] = 'Widok z tyłu',
        ['Set'] = 'Ustaw',
        ['Unknown'] = 'Nieznany',
        ['dark'] = 'ciemno',
        ['bright'] = 'jasno',
    },
}

local LANGUAGE_BY_ID = {
    [0] = 'en',
    [1] = 'en_gb',
    [2] = 'de',
    [3] = 'pl',
    [4] = 'ja',
}

local function selectLanguage()
    local langId = tonumber(electrics.values.translateLanguage) or 0
    activeLanguage = LANGUAGE_BY_ID[langId] or 'en'
end

local function tr(text)
    local dict = TRANSLATIONS[activeLanguage]
    if not dict then return text end
    return dict[text] or text
end

local function translateList(list)
    local out = {}
    for i, value in ipairs(list or {}) do out[i] = tr(value) end
    return out
end

local activeMmiType = 1

local BASE_LABEL_KEYS = {
    'Navigation', 'Note', 'Navigation is not installed.', 'Nav-Info', 'Destination',
    'Changer', 'Source', 'CD control', 'Sound',
    'Passenger', 'Driver', 'Setup AC', 'Seat heat.', 'Blower', 'Distribution',
    'auto', 'on', 'off',
    'Car', 'Version', 'Systems', 'Version information', 'Software version:', 'Nav. database version:',
    'The required data for', 'the service interval display', 'are not yet available.',
    'sports suspension plus', 'adaptive air suspension',
    'Telephone', 'Telephone is not installed.', 'Directory', 'Import', 'Edit', 'Options',
    'Find entry', 'Import all entries', 'From phone book', 'Telephone - T-Mobile',
    'Memory', 'Dial', 'End call', 'Phone book', 'Connected', 'Dialing',
    'Look! Safe to move?', 'Settings', 'Graphic', 'Rear View', 'Audi parking system',
    'Audi side assist', 'coming home', 'dark', 'bright',
    'Set', 'Unknown',
    'Display', 'Front volume', 'Front frequency', 'Rear volume', 'Rear frequency',
    'left', 'right', 'rear', 'front',
    'DSP BOSE', 'Sound focus', 'AudioPilot™', 'Driver',
    'Traffic report', 'Voice guidance', 'Audio during route guid.', 'Speech dialogue system', 'Telephone volume',
}

local MMI_TYPE_DATA = {
    [1] = {
        VERSION_INFO = {
            mainLabel = 'Version information',
            line1 = 'Software version:',
            line2 = 'HNav_EU_K0257_6_D1',
            line3 = 'Nav. database version:',
            line4 = '8R0060884GH ECE 6.29.1',
        },
        SIMPLE = {
            mediaTitle = 'CD 1',
            mediaCorner1 = 'Changer',
            mediaCorner3 = 'CD control',
            mediaCorner4 = 'Sound',
            unknownSong = 'Unknown',
            parkingTitle = 'Audi parking system',
            parkingWarning = 'Look! Safe to move?',
            parkingSet = 'Set',
        },
    },

    [2] = {
        VERSION_INFO = {
            mainLabel = 'Version',
            line1 = 'SW: C6-HU 55.7.0 0835',
            line2 = 'HW: C6-HU 6350D2.0',
            line3 = 'FC SW: 03501AFC6AB320870',
            line4 = 'FC PS: 0870 FC HW: H07',
        },
        SIMPLE = {
            mediaTitle = 'CD 1',
            mediaCorner1 = 'Changer',
            mediaCorner3 = 'CD control',
            mediaCorner4 = 'Sound',
            unknownSong = 'Unknown',
            parkingTitle = 'Audi parking system',
            parkingWarning = 'Look! Safe to move?',
            parkingSet = 'Set',
        },
    },

    [3] = {
        SIMPLE = {
            mediaTitle = 'CD 1',
            mediaCorner1 = 'Changer',
            mediaCorner3 = 'CD control',
            mediaCorner4 = 'Sound',
            unknownSong = 'Unknown',
            parkingTitle = 'Audi parking system',
            parkingWarning = 'Look! Safe to move?',
            parkingSet = 'Set',
        },
    },
}

local function selectMmiType()
    local t = tonumber(electrics.values.mmiType) or 1
    activeMmiType = MMI_TYPE_DATA[t] and t or 1
end

local function activeMmiData()
    return MMI_TYPE_DATA[activeMmiType] or MMI_TYPE_DATA[1]
end

local function translatedMap(map)
    local out = {}
    for k, v in pairs(map or {}) do out[k] = type(v) == 'string' and tr(v) or v end
    return out
end

local function buildLabels(extra)
    local labels = {}
    for _, key in ipairs(BASE_LABEL_KEYS) do labels[key] = tr(key) end
    for k, v in pairs(extra or {}) do labels[k] = type(v) == 'string' and tr(v) or v end
    return labels
end

local function suspensionList()
    return (electrics.values.mmi_suspensionType == 'sport') and CAR_SUSPENSION_SPORT or CAR_SUSPENSION_AIR
end

-- Optional items that are conditionally inserted into a base list.
local OPTIONAL_ITEMS = {
    CAR_SYSTEMS = {
        { item = 'Audi parking system', 
          condition = function() return (electrics.values.rearParkingSensorsEnabled or 0) == 1 end },
        { item = 'Audi side assist', 
          condition = function() return (electrics.values.sideAssistEnabled or 0) == 1 end },
        { item = 'Background lighting', 
          condition = function() return (electrics.values.ambientLightsEnabled or 0) == 1 end },
    },
}

local DETAIL_VIEW_LABELS = {
    [1] = 'Battery level',
    [2] = 'Service interval display',
    [3] = 'Vehicle ID Number',
    [4] = 'Audi parking system',
    [5] = 'Central locking',
    [6] = 'Tire pressure monitoring',
    [7] = 'Audi side assist',
    [8] = 'Background lighting',
    [9] = 'Exterior lighting',
    [10] = 'Windshield wipers',
    [13] = 'Audi parking system',
    [14] = 'Front volume',
    [15] = 'Front frequency',
    [16] = 'Rear volume',
    [17] = 'Rear frequency',
}

local function buildList(name)
    local base = MENU_ITEMS[name]
    if not base then return {} end
    local opts = OPTIONAL_ITEMS[name]
    
    local result = {}
    
    -- Add static base items
    for _, v in ipairs(base) do
        result[#result + 1] = v
    end
    
    -- Add active conditional items
    if opts then
        for _, opt in ipairs(opts) do
            if opt.condition() then
                result[#result + 1] = opt.item
            end
        end
    end

    -- Sort the entire list alphabetically
    table.sort(result)

    return result
end

local function buildContacts()
    local male, female, service = loadContacts()
    local merged, genderMap = {}, {}
    for _, name in ipairs(service) do merged[#merged+1] = name end
    for _, name in ipairs(male)    do merged[#merged+1] = name; genderMap[name] = "male"   end
    for _, name in ipairs(female)  do merged[#merged+1] = name; genderMap[name] = "female" end
    table.sort(merged)
    return merged, genderMap
end

local function rebuildMenuItems()
    local data = activeMmiData()
    local items = {}
    for k, v in pairs(MENU_ITEMS) do
        items[k] = type(v) == 'table' and translateList(v) or tr(v)
    end
    items.CAR_SYSTEMS = translateList(buildList('CAR_SYSTEMS'))
	local climateItems = {}
    for _, v in ipairs(MENU_ITEMS.CLIMATE) do climateItems[#climateItems + 1] = v end
    if (electrics.values.rearSeatHeating or 0) == 1 then
        climateItems[#climateItems + 1] = 'Aux. heating'
        climateItems[#climateItems + 1] = 'Aux. vent'
    end
    items.CLIMATE = translateList(climateItems)
    -- Conditionally add DSP BOSE before Volume settings
    local soundItems = {}
    for i, v in ipairs(MENU_ITEMS.MEDIA_SOUND) do
        if i == 5 and (electrics.values.boseAudioSystem or 0) == 1 then
            soundItems[#soundItems + 1] = 'DSP BOSE'
        end
        soundItems[#soundItems + 1] = v
    end
    items.MEDIA_SOUND = translateList(soundItems)
    local merged, genderMap = buildContacts()
	items.CONTACTS  = merged
	items.GENDERMAP = genderMap
	local rawChanger, rawSources = loadMedia()
	local changer = {}
	for i, c in ipairs(rawChanger) do changer[i] = c .. ' - ' .. tr(rawSources[i] or '') end
	items.MEDIA_CHANGER = changer
	electrics.values.mmi_changerTitle = changer[changerIdx] or 'CD 1'
	electrics.values.mmi_sourceLabel  = tr(rawSources[changerIdx] or 'BT Audio')
	items.CAR_SUSPENSION = translateList(suspensionList())
    items.LABELS = buildLabels(data.LABELS)
    items.VERSION_INFO = translatedMap(data.VERSION_INFO)
    items.SIMPLE = translatedMap(data.SIMPLE)
	electrics.values.mmi_menu_items = jsonEncode(items)
end

local function totalContacts()
    local male, female, service = loadContacts()
    return #male + #female + #service
end

-- Maximum scroll index per [menu][submenu]. 999 = unbounded (song list).
-- Entries for menus 6 and 7 that depend on totalContacts() are placeholders here;
-- they are patched to real values by refreshContactScrollLimits() called from init().
local SUBMENU_MAX = {
    [2] = {[0] = 999, [1] = #MENU_ITEMS.MEDIA_CHANGER, [2] = #MENU_ITEMS.MEDIA_SOURCE,
                      [3] = #MENU_ITEMS.MEDIA_CONTROL,  [4] = #MENU_ITEMS.MEDIA_SOUND},
    [4] = {[0] = #MENU_ITEMS.CLIMATE, [1] = 1, [2] = 1, [3] = 1, [4] = 1},
    [5] = {[0] = #MENU_ITEMS.CAR_SUSPENSION, [3] = #MENU_ITEMS.CAR_SYSTEMS + 2, [4] = 1, [9] = 3},
    [6] = {[0] = 1, [1] = 1, [3] = #MENU_ITEMS.NAME_EDIT, [4] = #MENU_ITEMS.NAME_CALL},
    [7] = {[0] = 1, [1] = 1, [3] = 1, [4] = 1},
}

local function refreshContactScrollLimits()
    local total = totalContacts()
    SUBMENU_MAX[6][0] = total + 1
    SUBMENU_MAX[6][1] = 2 + total
    SUBMENU_MAX[7][1] = total
end

-- Saved scroll positions keyed by "menu_submenu".
local savedScrolls = {}

-- Initial scroll values for specific menu/submenu combos (suspension starts on "automatic").
local SCROLL_DEFAULTS = {
    ['5_0'] = 3,
}

-- Submenus that inherit their scroll from another key (keeps contact selection in sync across tel flow).
local SCROLL_FALLBACK = {
    ['7_4'] = '7_1',
    ['7_3'] = '7_1',
}

-- Submenus whose scroll is always inherited; they must not overwrite the source key.
local SKIP_SAVE = {
    ['7_3'] = true,
    ['7_4'] = true,
}

-- Saved scroll position while inside the CAR_SYSTEMS list (separate from inter-menu saves).
-- Detail view default scroll values
local DV_DEFAULTS = {
    [7]  = function() return electrics.values.mmi_sideAssistLevel or 1 end,
    [8]  = function()
        local val = electrics.values.mmi_bgLightingLevel or 0
        local scroll = math.floor(val * 4 + 1.5)
        return scroll
    end,
    [11] = function() return electrics.values.mmi_centreVentLevel or 4 end,
    [12] = function() return (electrics.values.mmi_comingHomeDuration or 3) + 1 end,
    [14] = function() return electrics.values.mmi_parkingFrontVolume or 5 end,
    [15] = function() return electrics.values.mmi_parkingFrontFreq or 5 end,
    [16] = function() return electrics.values.mmi_parkingRearVolume or 5 end,
    [17] = function() return electrics.values.mmi_parkingRearFreq or 5 end,
    [20] = function() return electrics.values.mmi_soundBalance or 10 end,
    [21] = function() return electrics.values.mmi_soundFader or 10 end,
    [22] = function() return electrics.values.mmi_soundTreble or 10 end,
    [23] = function() return electrics.values.mmi_soundBass or 10 end,
    [26] = function() return electrics.values.mmi_volTrafficReport or 3 end,
    [27] = function() return electrics.values.mmi_volVoiceGuidance or 3 end,
    [28] = function() return electrics.values.mmi_volAudioRouteGuid or 3 end,
    [29] = function() return electrics.values.mmi_volSpeechDialogue or 3 end,
    [30] = function() return electrics.values.mmi_volTelephone or 3 end,
}

local function pushDv(newDv)
    table.insert(dvStack, {
        dv = electrics.values.mmi_detailView or 0,
        scroll = electrics.values.mmiscroll or 1
    })
    electrics.values.mmi_detailView = newDv
    local fn = DV_DEFAULTS[newDv]
    electrics.values.mmiscroll = fn and fn() or 1
end

local function popDv()
    local prev = table.remove(dvStack)
    if prev then
        electrics.values.mmi_detailView = prev.dv
        electrics.values.mmiscroll = prev.scroll
    else
        electrics.values.mmi_detailView = 0
    end
    return electrics.values.mmi_detailView
end

local function clearDvStack()
    dvStack = {}
    if (electrics.values.mmi_detailView or 0) > 0 then
        electrics.values.mmi_detailView = 0
    end
end

-- Per-frame mmimax updater based on current detail view (replaces scattered override sections)
local function applyDvMmimax(menu, submenu)
    -- hvac.lua owns mmimax while any HVAC overlay is active
    if (electrics.values.hvac_context or 0) > 0 then return end

    local dv = electrics.values.mmi_detailView or 0
    if menu == 5 and submenu == 3 then
        if dv == 0 then electrics.values.mmimax = #buildList('CAR_SYSTEMS')
        elseif dv == 5  then electrics.values.mmimax = #MENU_ITEMS.CAR_CENTRAL_LOCKING
        elseif dv == 7 or dv == 8 then electrics.values.mmimax = 5
        elseif dv == 9  then electrics.values.mmimax = #MENU_ITEMS.CAR_EXT_LIGHTING
        elseif dv == 10 then electrics.values.mmimax = #MENU_ITEMS.CAR_WIPERS
        elseif dv == 12 then electrics.values.mmimax = 7
        elseif dv == 13 then electrics.values.mmimax = #MENU_ITEMS.PARKING_SETTINGS
        elseif dv >= 14 and dv <= 17 then electrics.values.mmimax = 9
        end
        electrics.values.mmi_detailLabel = tr(DETAIL_VIEW_LABELS[dv] or '')
    elseif menu == 2 and submenu == 4 then
        if dv == 0 then electrics.values.mmimax = SUBMENU_MAX[2][4]
        elseif dv >= 20 and dv <= 23 then electrics.values.mmimax = 19
        elseif dv == 24 then electrics.values.mmimax = #MENU_ITEMS.DSP_BOSE
        elseif dv == 25 then electrics.values.mmimax = #MENU_ITEMS.VOLUME_SETTINGS
        elseif dv >= 26 and dv <= 30 then electrics.values.mmimax = 5
        end
    elseif menu == 4 and submenu == 0 then
        if dv == 11 then electrics.values.mmimax = 7
        else electrics.values.mmimax = SUBMENU_MAX[4][0]
        end
    end
end

local function scrollKey(menu, submenu) return menu .. '_' .. submenu end

local function saveScroll(menu, submenu)
    if menu >= 0 and submenu >= 0 then
        local key = scrollKey(menu, submenu)
        if not SKIP_SAVE[key] then
            local current = electrics.values.mmiscroll
            if current then savedScrolls[key] = current end
        end
    end
end

local function getDefaultScroll(menu, submenu)
    local key = scrollKey(menu, submenu)
    if savedScrolls[key] then return savedScrolls[key] end
    local fallbackKey = SCROLL_FALLBACK[key]
    if fallbackKey then return savedScrolls[fallbackKey] or SCROLL_DEFAULTS[key] or 1 end
    return SCROLL_DEFAULTS[key] or 1
end

-- OK-button actions per [menu][submenu]. Return a submenu override or nil.
local OK_ACTIONS = {
    [2] = {
        [0] = function(scroll)
            local total   = electrics.values['audi6_nrOfSongs'] or 1
            local current = electrics.values['current_music_index'] or 1
            if scroll >= 1 and scroll <= total then
                electrics.values['music' .. current .. '_state'] = 0
                electrics.values['current_music_index']          = scroll
                electrics.values['music' .. scroll .. '_state']  = 1
                electrics.values['screen2_state']                = 0
                electrics.values['audi6_musicPaused']            = 0
            end
        end,
        [1] = function(scroll) if scroll == 1 then return 0 end end,
        [2] = function(scroll) if scroll == 1 then return 0 end end,
        [4] = function(scroll)
            local dv = electrics.values.mmi_detailView or 0
            if dv >= 20 and dv <= 23 then
                local valKeys = {[20]='mmi_soundBalance', [21]='mmi_soundFader', [22]='mmi_soundTreble', [23]='mmi_soundBass'}
                electrics.values[valKeys[dv]] = electrics.values.mmiscroll
                popDv()
                return nil
            end
            if dv == 24 then
                if scroll == 1 then
                    electrics.values.mmi_soundFocusMode = 1 - (electrics.values.mmi_soundFocusMode or 0)
                elseif scroll == 2 then
                    electrics.values.mmi_audioPilot = 1 - (electrics.values.mmi_audioPilot or 0)
                end
                return nil
            end
            if dv == 25 then
                if scroll >= 1 and scroll <= 5 then pushDv(25 + scroll) end
                return nil
            end
            if dv >= 26 and dv <= 30 then
                local valKeys = {[26]='mmi_volTrafficReport', [27]='mmi_volVoiceGuidance', [28]='mmi_volAudioRouteGuid', [29]='mmi_volSpeechDialogue', [30]='mmi_volTelephone'}
                electrics.values[valKeys[dv]] = electrics.values.mmiscroll
                popDv()
                return nil
            end
            local hasBose = (electrics.values.boseAudioSystem or 0) == 1
            local volPos = hasBose and 6 or 5
            if scroll == 1 then pushDv(20)
            elseif scroll == 2 then pushDv(21)
            elseif scroll == 3 then pushDv(22)
            elseif scroll == 4 then pushDv(23)
            elseif scroll == 5 and hasBose then pushDv(24)
            elseif scroll == volPos then pushDv(25)
            end
            return nil
        end,
    },
    [4] = {
		[0] = function(scroll)
			if (electrics.values.mmi_detailView or 0) == 11 then
				electrics.values.mmi_centreVentLevel = scroll
				popDv()
				return nil
			end
			if     scroll == 1 then electrics.values.button_econ          = 1 - (electrics.values.button_econ          or 0)
			elseif scroll == 2 then electrics.values.button_recirculation = 1 - (electrics.values.button_recirculation or 0)
			elseif scroll == 3 then
				electrics.values.mmi_synchron = 1 - (electrics.values.mmi_synchron or 0)
				if electrics.values.mmi_synchron == 1 then electrics.values.button_airflow2 = electrics.values.button_airflow1 or 0 end
			elseif scroll == 4 then pushDv(11)
			elseif scroll == 5 then electrics.values.mmi_auxHeatingActive = 1 - (electrics.values.mmi_auxHeatingActive or 0)
			elseif scroll == 6 then electrics.values.mmi_auxVentActive    = 1 - (electrics.values.mmi_auxVentActive or 0)
			end
		end,
	},
    [5] = {
        [0] = function(scroll)
            local sport = (electrics.values.mmi_suspensionType or 'air') == 'sport'
            local damperMode, springMode, swayMode
            if sport then                              -- comfort / dynamic / sport
                damperMode = { [1]='soft',    [2]='regular', [3]='hard'    }
                springMode = { [1]='regular', [2]='regular', [3]='regular' }  -- no active springs; ignored
                swayMode   = { [1]='soft',    [2]='regular', [3]='hard'    }
            else                                       -- lift / comfort / automatic / dynamic
                damperMode = { [1]='soft',    [2]='regular', [3]='regular', [4]='hard'    }
                springMode = { [1]='high',    [2]='regular', [3]='regular', [4]='low'     }
                swayMode   = { [1]='soft',    [2]='regular', [3]='regular', [4]='regular' }
            end
            if damperMode[scroll] then
                electrics.values.mmi_suspensionDamper = damperMode[scroll]
                electrics.values.mmi_suspensionSpring = springMode[scroll]
                electrics.values.mmi_suspensionSway   = swayMode[scroll]
                savedScrolls['5_0'] = scroll
            end
        end,
        [3] = function(scroll)
            local dv = electrics.values.mmi_detailView or 0
            -- Read-only detail views: OK does nothing
            if dv == 1 or dv == 2 or dv == 3 or dv == 6 then
                return nil
            end
            if dv == 5 then
				local includeKeys = {'lockInclude_FR', 'lockInclude_RL', 'lockInclude_RR', 'lockInclude_trunk', nil}
				local iKey = includeKeys[scroll]
				if iKey then
					electrics.values[iKey] = 1 - (electrics.values[iKey] or 1)
				elseif scroll == 5 then
					electrics.values.centralLock = 1 - (electrics.values.centralLock or 0)
				end
                return nil
            end
            if dv == 7 then
                electrics.values.mmi_sideAssistLevel = electrics.values.mmiscroll
                popDv()
                return nil
            end
            if dv == 8 then
                local scroll = electrics.values.mmiscroll or 1
                local newVal = (scroll - 1) / 4
                electrics.values.mmi_bgLightingLevel = newVal
                popDv()
                return nil
            end
            if dv == 12 then
                electrics.values.mmi_comingHomeDuration = electrics.values.mmiscroll - 1
                electrics.values.mmi_comingHomeActive = electrics.values.mmiscroll > 1 and 1 or 0
                popDv()
                return nil
            end
            if dv == 9 then
                if scroll == 1 then pushDv(12)
                elseif scroll == 2 then
                    electrics.values.mmi_leavingHomeActive = 1 - (electrics.values.mmi_leavingHomeActive or 0)
                elseif scroll == 3 then
                    electrics.values.mmi_drlActive = 1 - (electrics.values.mmi_drlActive or 0)
                end
                return nil
            end
            if dv == 10 then
				local nextState = 1 - (electrics.values.mmi_wiperServicePos or 0)
				electrics.values.mmi_wiperServicePos = nextState
				wiperServiceStart  = electrics.values.wipers_position or 0
				wiperServiceTarget = nextState / 2
				wiperServicePeriod = 0
				wiperServiceActive = true
				return nil
			end
            if dv == 13 then
                if scroll == 1 then
                    local cur = electrics.values.mmi_parkingDisplayMode or 0
                    if cur == 0 and electrics.values.reverseCameraEnabled then
                        electrics.values.mmi_parkingDisplayMode = 1
                    else
                        electrics.values.mmi_parkingDisplayMode = 0
                    end
                elseif scroll == 2 then pushDv(14)
                elseif scroll == 3 then pushDv(15)
                elseif scroll == 4 then pushDv(16)
                elseif scroll == 5 then pushDv(17)
                end
                return nil
            end
            if dv >= 14 and dv <= 17 then
                local valKeys = {[14]='mmi_parkingFrontVolume', [15]='mmi_parkingFrontFreq', [16]='mmi_parkingRearVolume', [17]='mmi_parkingRearFreq'}
                electrics.values[valKeys[dv]] = electrics.values.mmiscroll
                popDv()
                return nil
            end

            -- Dynamically fetch the current alphabetically sorted list
            local currentList = buildList('CAR_SYSTEMS')
            local selectedItem = currentList[scroll]

            -- Map item string directly to its respective menu detail ID
            local stringToId = {
                ['Battery level']             = 1,
                ['Service interval display']  = 2,
                ['Vehicle ID Number']         = 3,
                ['Audi parking system']       = 13,
                ['Central locking']           = 5,
                ['Tire pressure monitoring']  = 6,
                ['Audi side assist']          = 7,
                ['Background lighting']       = 8,
                ['Exterior lighting']         = 9,
                ['Windshield wipers']         = 10,
            }

            local targetView = stringToId[selectedItem]
            if targetView then pushDv(targetView) end
        end,
    },
    [7] = {
		[1] = function(scroll)
            if (electrics.values.phoneEnabled or 0) == 1 then return 4 end
        end,
	},
}

local function handleTelFlow(submenu, lastSubmenu, detail, dt, phoneOn)
    if not phoneOn then
        dialTimer, endCallTimer = 0, 0
        return 0, detail
    end

    if submenu == 0 then submenu = 1 end
    if submenu == 3 and lastSubmenu ~= 4 then submenu = lastSubmenu end
    if (detail == 1 or dialTimer > 0) and submenu ~= 3 and submenu ~= 4 then submenu = lastSubmenu end

    -- End call flow
    if submenu == 3 then
        if lastSubmenu ~= 3 then
            endCallTimer = 3.0
            electrics.values.mmi_detailView = 0; detail = 0
            phone_sounds.stopGreetingSound()
            phone_sounds.stopDialSound()
            phone_sounds.playEndCallSound()
        end
        endCallTimer = math.max(0, endCallTimer - dt)
        if endCallTimer == 0 then submenu = 1 end
    else
        endCallTimer = 0
    end

    -- Dial flow
    if submenu == 4 and detail == 0 then
        if lastSubmenu ~= 4 then dialTimer = 6.0; phone_sounds.playDialSound() end
        dialTimer = math.max(0, dialTimer - dt)
        if dialTimer == 0 then
            electrics.values.mmi_detailView = 1; detail = 1
            local contacts, genderMap = buildContacts()
            local name = contacts[electrics.values.mmiscroll or 1] or ""
            local customSound = phone_sounds.getContactSound(name)
            if customSound then phone_sounds.playContactSound(customSound)
            else phone_sounds.playGreetingSound(genderMap[name] or "male") end
        end
    else
        dialTimer = 0
    end

    return submenu, detail
end

local function handleOk(menu, submenu, scroll)
    local action = (OK_ACTIONS[menu] or {})[submenu]
    local override = nil
    if action then override = action(scroll) end
    electrics.values.mmi_ok = 0
    return override
end

-- The parking graphic should follow proximity, not merely the presence of
-- sensor entries. parkingSensorHits carries one distance per sensor on every
-- pass while the system runs, so a length check is true even with nothing
-- anywhere near the car. 1.5 m matches the distance at which the beeper
-- starts pulsing, so screen and sound now appear together.
local PARKING_SHOW_DISTANCE = 1.5

local function bumperWithin(list, threshold)
    if type(list) ~= "table" then return false end
    for i = 1, #list do
        local d = list[i]
        if type(d) == "number" and d < threshold then return true end
    end
    return false
end

local function computeActiveScreen(menu)
    local e = electrics.values
    local active = menu

    local climateActive = (e.hvac_context or 0) > 0
    if climateActive then
        active = SCREEN.CLIMATE
    elseif climateWasActive then
        if (e.mmi_detailView or 0) == 11 then
            e.mmi_detailView = 0
        end
        active = menu
    end
    climateWasActive = climateActive

    -- Skip parking override when parking settings are open (from any entry point)
    local dv = e.mmi_detailView or 0
    if dv >= 13 and dv <= 17 then
        e.mmi_activeScreen = active
        return
    end
    if dv < 13 or dv > 17 then
        parkingShowSettings = false
    end

    local toggleCount  = e.mmi_reverseCamToggle or 0
    local hasSensors   = (e.rearParkingSensorsEnabled or 0) == 1

    -- Cars fitted with a reverse camera default to the camera view, not the sensor graphic.
    -- Applied once per vehicle so the driver's own choice (parking settings or the BL toggle)
    -- is never overwritten afterwards.
    if not parkingCamDefaultDone and e.reverseCameraEnabled then
        e.mmi_parkingDisplayMode = 1
        parkingCamDefaultDone = true
    end

    local defaultCam = (e.mmi_parkingDisplayMode or 0) == 1 and e.reverseCameraEnabled and true or false

    if (e.mmi_detailView or 0) == 4 and hasSensors then
        if reverseShowCamera == nil then reverseShowCamera = defaultCam; lastReverseCamToggle = toggleCount end
        if e.reverseCameraEnabled and toggleCount ~= lastReverseCamToggle then
            reverseShowCamera = not reverseShowCamera; lastReverseCamToggle = toggleCount
            e.mmi_parkingDisplayMode = reverseShowCamera and 1 or 0
        end
        active = reverseShowCamera and SCREEN.REVERSE_CAM or SCREEN.PARKING
    elseif (e.reverse or 0) ~= 0 then
        local hasCam = e.reverseCameraEnabled and true or false
        if reverseShowCamera == nil then reverseShowCamera = defaultCam; lastReverseCamToggle = toggleCount end
        if hasCam and toggleCount ~= lastReverseCamToggle then
            reverseShowCamera = not reverseShowCamera; lastReverseCamToggle = toggleCount
            e.mmi_parkingDisplayMode = reverseShowCamera and 1 or 0
        end
        active = reverseShowCamera and SCREEN.REVERSE_CAM
            or (hasSensors and (e.button_parkingsensors or 0) ~= 0 and SCREEN.PARKING or active)
    else
        local psh = e.parkingSensorHits
        if hasSensors and (e.button_parkingsensors or 0) ~= 0
            and bumperWithin(psh and psh.frontBumper, PARKING_SHOW_DISTANCE) then
            active = SCREEN.PARKING
        end
        reverseShowCamera = nil; lastReverseCamToggle = nil
    end

    -- Reset submenu tracking when parking view is active so BL press is always detectable
    -- But preserve submenu when a detail view is active (user was in a real menu)
    if active == SCREEN.PARKING or active == SCREEN.REVERSE_CAM then
        if (e.mmi_detailView or 0) == 0 then
            e.submenu = 0
            lastSubmenu = 0
        end
    end

    e.mmi_activeScreen = active
end

-- Ignition on/off: save and restore menu state
local function handleIgnition(ignition)
    if ignition == 0 and lastIgnition > 0 then
        savedMenu, savedSubmenu = electrics.values.mmiMenu or 0, electrics.values.submenu or 0
        electrics.values.mmiMenu, electrics.values.submenu = 0, 0
        savedBgLighting = electrics.values.mmi_bgLightingLevel or 0
        electrics.values.mmi_bgLightingLevel = 0
    elseif ignition > 0 and lastIgnition == 0 then
        electrics.values.mmiMenu, electrics.values.submenu = savedMenu, savedSubmenu
        if savedBgLighting then
            electrics.values.mmi_bgLightingLevel = savedBgLighting
            savedBgLighting = nil
        end
    end
    lastIgnition = ignition
end

-- Rebuild menu items when vehicle config electrics change
local function syncVehicleConfig()
    local dirty = false

    local sensors = electrics.values.rearParkingSensorsEnabled or 0
    if sensors ~= lastParkingSensors then lastParkingSensors = sensors; dirty = true end

    local sa = electrics.values.sideAssistEnabled or 0
    if sa ~= lastSideAssist then lastSideAssist = sa; dirty = true end

    local amb = electrics.values.ambientLightsEnabled or 0
    if amb ~= lastAmbientLights then lastAmbientLights = amb; dirty = true end

    local rh = electrics.values.rearSeatHeating or 0
    if rh ~= lastRearSeatHeating then
        lastRearSeatHeating = rh; dirty = true
        local count = #MENU_ITEMS.CLIMATE
        if rh == 1 then count = count + 2 end
        SUBMENU_MAX[4][0] = count
    end

    if dirty then rebuildMenuItems() end

    local soundCount = #MENU_ITEMS.MEDIA_SOUND
    if (electrics.values.boseAudioSystem or 0) == 1 then soundCount = soundCount + 1 end
    SUBMENU_MAX[2][4] = soundCount
end

-- Detect BL press from parking view → open parking settings
local function handleParkingSettingsShortcut()
    local as = electrics.values.mmi_activeScreen or 0
    local newSub = electrics.values.submenu or 0
    if (as == SCREEN.PARKING or as == SCREEN.REVERSE_CAM) and newSub == 3 and lastSubmenu ~= 3 then
        electrics.values.mmiMenu = 5
        electrics.values.submenu = 3
        pushDv(13)
        lastMenu = 5
        lastSubmenu = 3
        parkingShowSettings = true
    end
end

-- Handle menu changes: clear detail view, set default submenu
local function handleMenuChange(menu, submenu, detail)
    if menu ~= lastMenu then
        if detail > 0 then clearDvStack() end
        detail = electrics.values.mmi_detailView or 0
        submenu = (menu == 5 and (electrics.values.mmi_hasAdaptiveSuspension or 0) == 0) and 3 or 0
    end
    -- Clear detail view when switching submenus via corner buttons
    if submenu ~= lastSubmenu and submenu ~= 0 and menu == lastMenu and detail > 0 then
        clearDvStack()
        detail = 0
    end
    return submenu, detail
end

-- Submenu 4 (parking camera toggle) entry guards
local function guardParkingSubmenu(submenu, inReverse, detail)
    if submenu == 4 and lastSubmenu ~= 4 then
        if electrics.values.reverseCameraEnabled and (electrics.values.button_parkingsensors or 0) == 0 then
            return lastSubmenu
        elseif inReverse and electrics.values.reverseCameraEnabled then
            electrics.values.mmi_reverseCamToggle = (electrics.values.mmi_reverseCamToggle or 0) + 1
            return 0
        elseif inReverse or (electrics.values.mmi_parkingActive or 0) == 1 or detail > 0 then
            return lastSubmenu
        end
    end
    return submenu
end

-- Validate submenu against SUBMENU_MAX + per-menu fallbacks
local function validateSubmenu(menu, submenu)
    if submenu ~= lastSubmenu and not (SUBMENU_MAX[menu] or {})[submenu] then submenu = lastSubmenu end
    if menu == 5 and submenu == 0 and (electrics.values.mmi_hasAdaptiveSuspension or 0) == 0 then
        submenu = lastSubmenu ~= 0 and lastSubmenu or 3
    end
    return submenu
end

-- Per-menu submenu routing (NAV lock, NAME phone guard, TEL flow, climate corners)
local function routeSubmenu(menu, submenu, detail, dt)
    local phoneOn = (electrics.values.phoneEnabled or 0) == 1
    if menu == 1 then
        return 0, detail
    elseif menu == 4 and submenu >= 1 and submenu <= 4 then
        -- Corner buttons on Setup AC: match the JS corner labels.
        -- Driver:    TL=Blower(1)  TR=Seat heat.(2)  BL=Distribution(4)
        -- Passenger: TL=Seat heat.(3)  TR=Blower(1)  BR=Distribution(5)
        local currentCtx = electrics.values.hvac_context or 0
        local isPassenger = (currentCtx == 3 or currentCtx == 5)  -- SEAT_R or AIR_R
        local hvacForCorner = isPassenger
            and {[1] = 3, [2] = 1, [4] = 5}    -- TL=SEAT_R, TR=FAN, BR=AIR_R
            or  {[1] = 1, [2] = 2, [3] = 4}    -- TL=FAN, TR=SEAT_L, BL=AIR_L
        local target = hvacForCorner[submenu]
        if not target then
            -- Empty corner (e.g. BL in passenger mode, BR in driver mode)
            return 0, detail
        end
        if currentCtx == target then
            climateCornerCtx = 0
            electrics.values.mmi_hvac_request = -1
        else
            climateCornerCtx = target
            electrics.values.mmi_hvac_request = target
        end
        return 0, detail
    elseif menu == 6 and not phoneOn then
        return 0, detail
    elseif menu == 7 then
        return handleTelFlow(submenu, lastSubmenu, detail, dt, phoneOn)
    else
        dialTimer, endCallTimer = 0, 0
        return submenu, detail
    end
end

-- Handle scroll & menu state transitions when menu or submenu changes
local function handleStateTransition(menu, submenu)
    if menu ~= lastMenu or submenu ~= lastSubmenu then
        saveScroll(lastMenu, lastSubmenu)
        local defined = (SUBMENU_MAX[menu] or {})[submenu]
        if menu ~= lastMenu or defined then
            local mmimax = defined or 6
            if menu == 2 and submenu == 0 then mmimax = math.max(1, electrics.values['audi6_nrOfSongs'] or mmimax) end
            electrics.values.mmimax    = mmimax
            electrics.values.mmiscroll = getDefaultScroll(menu, submenu)
            if menu == 4 and submenu == 6 then
                electrics.values.mmiscroll = electrics.values.mmi_centreVentLevel or 4
            end
            if menu == 2 and lastMenu ~= 2 and submenu == 0 then
                electrics.values.mmiscroll = electrics.values['current_music_index'] or 1
            end
        end
        lastMenu, lastSubmenu = menu, submenu
    end
end

-- Apply suspension hardware parameters
local function applySuspension()
    local dm = electrics.values.mmi_suspensionDamper
    if not dm then return end
    local sm, sw = electrics.values.mmi_suspensionSpring, electrics.values.mmi_suspensionSway
    for _, c in ipairs({
        { name='adaptiveFrontDamper',  param='damperMode',    value=dm },
        { name='adaptiveRearDamper',   param='damperMode',    value=dm },
        { name='activeFrontSpring',    param='springMode',    value=sm },
        { name='activeRearSpring',     param='springMode',    value=sm },
        { name='adaptiveFrontSwayBar', param='torsionBarMode',value=sw },
        { name='adaptiveRearSwayBar',  param='torsionBarMode',value=sw },
    }) do
        local ctrl = controller.getController(c.name)
        if ctrl then ctrl.setParameters({ [c.param] = c.value }) end
    end
    electrics.values.mmi_suspensionDamper = nil
end

local function update(dt)
    local ignition  = electrics.values.ignitionLevel or 0
    local inReverse = (electrics.values.reverse or 0) ~= 0

    handleIgnition(ignition)
    if ignition == 0 then return end

    syncVehicleConfig()
    handleParkingSettingsShortcut()

    if inReverse ~= lastReverse then parkingShowSettings = false end

    local menu    = electrics.values.mmiMenu or 0
    local submenu = electrics.values.submenu or 0
    local detail  = electrics.values.mmi_detailView or 0
    local rawSubmenu = submenu  -- snapshot before any processing

    if inReverse and not lastReverse then electrics.values.mmi_parkingActive = nil end

    -- Same-menu button re-press: pressing e.g. CD while in a CD submenu → back to home page
    for btn, menuId in pairs(MENU_BUTTONS) do
        local val = electrics.values[btn] or 0
        if prevMenuButtons[btn] ~= nil and val ~= prevMenuButtons[btn] then
            if menu == menuId and (submenu ~= 0 or detail > 0) then
                electrics.values.submenu = 0
                submenu = 0
                clearDvStack()
                detail = 0
            end
        end
        prevMenuButtons[btn] = val
    end

    submenu, detail = handleMenuChange(menu, submenu, detail)
    submenu = guardParkingSubmenu(submenu, inReverse, detail)

    -- Back out of detail view (stack-based, only when back button transitions submenu from non-zero to zero)
    if submenu == 0 and lastSubmenu ~= 0 and #dvStack > 0 and detail > 0 then
        detail = popDv()
        submenu = lastSubmenu
    end

    -- HVAC overlay management (works for both MMI corners and physical buttons)
    local hvacActive = (electrics.values.hvac_context or 0) > 0
    if hvacActive then
        -- OK button → dismiss any active HVAC overlay
        if (electrics.values.mmi_ok or 0) == 1 then
            electrics.values.mmi_ok = 0
            electrics.values.mmi_hvac_request = -1
            climateCornerCtx = 0
        end
    else
        -- Overlay just closed externally (timer, menu change) → clean up
        if climateCornerCtx > 0 then climateCornerCtx = 0 end
    end

    -- OK button
    if (electrics.values.mmi_ok or 0) == 1 then
        local override = handleOk(menu, submenu, electrics.values.mmiscroll or 1)
        if override ~= nil then submenu = override end
    end

    -- Climate overlay corner redirect: when the HVAC overlay is showing (from any menu),
    -- corner button presses control the overlay, not the underlying menu.
    -- Uses rawSubmenu vs prevRawSubmenu (not lastSubmenu) to avoid false negatives
    -- when lastSubmenu happens to equal the corner number from a previous menu.
    local hvacCtx = electrics.values.hvac_context or 0
    if hvacCtx > 0 and rawSubmenu >= 1 and rawSubmenu <= 4 and rawSubmenu ~= prevRawSubmenu then
        local isPassenger = (hvacCtx == 3 or hvacCtx == 5)  -- SEAT_R or AIR_R
        local hvacForCorner = isPassenger
            and {[1] = 3, [2] = 1, [4] = 5}    -- TL=SEAT_R, TR=FAN, BR=AIR_R
            or  {[1] = 1, [2] = 2, [3] = 4}    -- TL=FAN, TR=SEAT_L, BL=AIR_L
        local target = hvacForCorner[submenu]
        if target then
            if hvacCtx == target then
                climateCornerCtx = 0
                electrics.values.mmi_hvac_request = -1
            else
                climateCornerCtx = target
                electrics.values.mmi_hvac_request = target
            end
        end
        submenu = lastSubmenu  -- restore so the underlying menu is unaffected
    end
    prevRawSubmenu = rawSubmenu

    submenu = validateSubmenu(menu, submenu)
    submenu, detail = routeSubmenu(menu, submenu, detail, dt)

    electrics.values.submenu           = submenu
    electrics.values.mmi_activeSubmenu = submenu

    handleStateTransition(menu, submenu)
    applyDvMmimax(menu, submenu)
    applySuspension()

    if (electrics.values.mmi_synchron or 0) == 1 then
        electrics.values.button_airflow2 = electrics.values.button_airflow1 or 0
    end

    -- Smoothly interpolate wiper service position: (1 - cos(period))/2, same curve as front wipers
    if wiperServiceActive then
        electrics.values.mmi_wiperServiceBusy = 1
        wiperServicePeriod = wiperServicePeriod + dt * WIPER_SERVICE_SPEED
        if wiperServicePeriod >= math.pi then
            electrics.values.wipers_position = wiperServiceTarget
            wiperServiceActive = false
            electrics.values.mmi_wiperServiceBusy = 0
        else
            local blend = (1 - math.cos(wiperServicePeriod)) / 2
            electrics.values.wipers_position = wiperServiceStart + (wiperServiceTarget - wiperServiceStart) * blend
        end
    end

    lastReverse = inReverse
    computeActiveScreen(menu)
end

local function init()
    selectLanguage()
    selectMmiType()
    lastParkingSensors = -1
    lastSideAssist     = -1
	lastAmbientLights  = -1
	lastRearSeatHeating = -1
    ensureDefaultFiles()
    refreshContactScrollLimits()
	-- detect suspension type BEFORE the menu is built
    local frontAdaptive = (electrics.values.adaptiveStrutsFront or 0) == 1
    local hasAir   = frontAdaptive and (electrics.values.adaptiveSpringsRear or 0) == 1
    local hasSport = frontAdaptive and (electrics.values.adaptiveStrutsRear or 0) == 1 and not hasAir
    electrics.values.mmi_hasAdaptiveSuspension = (hasAir or hasSport) and 1 or 0
    electrics.values.mmi_suspensionType = hasAir and 'air' or (hasSport and 'sport' or 'none')

    SUBMENU_MAX[5][0] = #suspensionList()     -- 3 for sport, 4 for air
    savedScrolls = {}
    savedScrolls['5_0'] = hasSport and 2 or 3 -- highlight Dynamic (sport) / Automatic (air)
    electrics.values.mmi_suspensionDamper = 'regular'
    electrics.values.mmi_suspensionSpring = 'regular'
    electrics.values.mmi_suspensionSway   = 'regular'
	electrics.values.lockInclude_FR    = electrics.values.lockInclude_FR    or 1
	electrics.values.lockInclude_RL    = electrics.values.lockInclude_RL    or 1
	electrics.values.lockInclude_RR    = electrics.values.lockInclude_RR    or 1
	electrics.values.lockInclude_trunk = electrics.values.lockInclude_trunk or 1
	electrics.values.mmi_sideAssistLevel = electrics.values.mmi_sideAssistLevel or 1
	local rawBg = electrics.values.mmi_bgLightingLevel
	if rawBg and rawBg > 1 then rawBg = (rawBg - 1) / 4 end  -- convert old 1-5 integer to 0-1
	electrics.values.mmi_bgLightingLevel = rawBg or 0.5
	electrics.values.mmi_extLightingLevel = electrics.values.mmi_extLightingLevel or 1
	electrics.values.mmi_comingHomeActive  = electrics.values.mmi_comingHomeActive or 1
	electrics.values.mmi_comingHomeDuration = electrics.values.mmi_comingHomeDuration or 4
    electrics.values.mmi_leavingHomeActive = electrics.values.mmi_leavingHomeActive or 1
    electrics.values.mmi_drlActive         = electrics.values.mmi_drlActive or 1
	electrics.values.mmi_centreVentLevel = electrics.values.mmi_centreVentLevel or 4
	electrics.values.mmi_wiperServicePos = electrics.values.mmi_wiperServicePos or 0
	wiperServiceTarget = (electrics.values.mmi_wiperServicePos or 0) / 2
	wiperServiceStart  = wiperServiceTarget
	wiperServicePeriod = 0
	wiperServiceActive = false
	electrics.values.mmi_wiperServiceBusy = 0
	electrics.values.mmi_auxHeatingActive = electrics.values.mmi_auxHeatingActive or 0
	electrics.values.mmi_auxVentActive    = electrics.values.mmi_auxVentActive or 0
	electrics.values.mmi_parkingDisplayMode = electrics.values.mmi_parkingDisplayMode or 0
	electrics.values.mmi_parkingFrontVolume = electrics.values.mmi_parkingFrontVolume or 5
	electrics.values.mmi_parkingFrontFreq   = electrics.values.mmi_parkingFrontFreq or 5
	electrics.values.mmi_parkingRearVolume  = electrics.values.mmi_parkingRearVolume or 5
	electrics.values.mmi_parkingRearFreq    = electrics.values.mmi_parkingRearFreq or 5
	electrics.values.mmi_parkingSettingsToggle = 0
	electrics.values.mmi_soundBalance = electrics.values.mmi_soundBalance or 10
	electrics.values.mmi_soundFader   = electrics.values.mmi_soundFader or 10
	electrics.values.mmi_soundTreble  = electrics.values.mmi_soundTreble or 10
	electrics.values.mmi_soundBass    = electrics.values.mmi_soundBass or 10
	electrics.values.mmi_soundFocusMode = electrics.values.mmi_soundFocusMode or 0
	electrics.values.mmi_audioPilot     = electrics.values.mmi_audioPilot or 0
	electrics.values.mmi_volTrafficReport  = electrics.values.mmi_volTrafficReport or 3
	electrics.values.mmi_volVoiceGuidance  = electrics.values.mmi_volVoiceGuidance or 3
	electrics.values.mmi_volAudioRouteGuid = electrics.values.mmi_volAudioRouteGuid or 3
	electrics.values.mmi_volSpeechDialogue = electrics.values.mmi_volSpeechDialogue or 3
	electrics.values.mmi_volTelephone      = electrics.values.mmi_volTelephone or 3
	
	lastMenu = -1
	lastSubmenu = -1
	dvStack = {}
	climateCornerCtx = 0
	savedMenu = 2
	savedSubmenu = 0

	electrics.values.mmiMenu = 2
	electrics.values.submenu = 0
	electrics.values.mmi_activeScreen = 2
	electrics.values.mmi_activeSubmenu = 0
	electrics.values.mmi_detailView = 0
end

M.onInit    = init
M.onReset   = init
M.updateGFX = update

return M