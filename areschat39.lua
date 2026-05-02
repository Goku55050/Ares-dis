local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local TeleportService = game:GetService("TeleportService")
local SocialService = game:GetService("SocialService")
local LocalPlayer = Players.LocalPlayer
local JobId = game.JobId

-- ============================================================
-- ELITE SNAPER PROTECTION (V11 — EXECUTION-ORDER-IMMUNE)
-- Seven-layer defence against __index metatable name/uid hooks.
-- Works even when aresontop (or any similar hook) executes FIRST.
--
--   Layer 0 — Hook-bypass reader (_readReal):
--     A universal function that recovers TRUE property values
--     from LocalPlayer even when __index is already hooked.
--     Uses three independent bypass techniques in priority order:
--       A) cloneref — creates a new Lua wrapper for the same
--          Roblox Player instance.  cloneref(LP) == LP → false,
--          so the hook's "t == LocalPlayer" guard never fires.
--       B) Upvalue extraction — scans the hooked __index for
--          its saved original function (oldIndex) and calls it
--          directly, completely bypassing the hook logic.
--       C) GetFullName() C++ fallback — for Name only.
--     Zero HTTP, zero yielding, zero lag.
--
--   Layer 1 — GetFullName() C++ bypass:
--     Confirms RealName via the C++ path after Layer 0.
--
--   Layer 2 — Spoof-detection comparison:
--     Re-reads LocalPlayer.Name through Lua indexing and
--     compares to the C++ result to detect active hooks.
--
--   Layer 3 — Identity verification:
--     Re-verifies RealUserId via _readReal in async context.
--     Never trusts raw LocalPlayer.UserId when hook detected.
--
--   Layer 4 — Hook neutralisation:
--     Scans hooked __index upvalues for boolean true (the
--     hackEnabled flag) and sets it to false, disabling the
--     hook at its source without removing or replacing it.
--
--   Layer 5 — Continuous integrity guard (every 5 seconds):
--     Re-extracts RealName via GetFullName(), RealUserId via
--     _readReal, and detects hook state continuously.  Also
--     refreshes the _origIndex reference in case aresontop
--     is injected AFTER this script starts.
--
--   Layer 6 — RealUserId privilege fence:
--     RealUserId replaces LocalPlayer.UserId everywhere:
--     ban list, CREATOR/OWNER role check, tag lookup, Firebase
--     SenderUid field, message ownership, private-chat canSee,
--     online registry, /tp2me — ALL use the bypass-verified value.
--
-- All outgoing Sender fields, join messages, /me emotes, and
-- reply detection use these locked values, so Ares ReChat is
-- fully immune to name-spoofers and UserId-spoofers regardless
-- of execution order.
-- ============================================================
--
-- LAYER 0 — Hook-bypass reader (runs BEFORE any variable capture)
--
-- aresontop hooks getrawmetatable(game).__index and checks
--   if hackEnabled and t == LocalPlayer then ...
-- Two independent techniques defeat this regardless of execution order:
--
--   A) cloneref(LocalPlayer) creates a second Lua wrapper around the
--      SAME Roblox Player instance.  The wrapper has a different Lua
--      identity, so  cloneref(LP) == LP  →  false.  aresontop's
--      "t == LocalPlayer" guard therefore never fires and the read
--      falls through to the ORIGINAL __index, returning the true value.
--      cloneref is available in Synapse, Script-Ware, Fluxus, Wave,
--      Delta, Solara, and virtually all modern executors.
--
--   B) Upvalue extraction — scan the hooked __index for a function
--      upvalue (the saved original __index, stored as "oldIndex" in
--      aresontop).  Calling it directly with (LocalPlayer, "UserId")
--      skips the hook entirely because the original Roblox __index
--      has no spoof logic.
--
--   C) GetFullName() C++ fallback — works for Name only (not UserId).
--
-- The reader tries A → B → C → raw read, returning the FIRST
-- successful result.  Zero HTTP, zero yielding, zero lag.
-- ============================================================

-- ============================================================
-- _getUpval(fn, i):
--   Wraps ALL known executor upvalue APIs in one helper.
--   debug.getupvalue returns (name, value) in standard Lua.
--   Some executors return (value) only, or (index, value).
--   We try every pattern and return the actual VALUE so callers
--   never have to worry about which API is underneath.
-- ============================================================
local function _getUpval(fn, i)
    -- Pattern: debug.getupvalue(fn, i) → (name, value)
    if debug and debug.getupvalue then
        local ok, a, b = pcall(debug.getupvalue, fn, i)
        if ok then
            if type(a) == "string" then return true, b   end  -- standard Lua
            if a ~= nil           then return true, a   end  -- value-only variant
        end
    end
    -- Pattern: getupvalue(fn, i) → (name, value) or (value)
    if getupvalue then
        local ok, a, b = pcall(getupvalue, fn, i)
        if ok then
            if type(a) == "string" then return true, b   end
            if a ~= nil           then return true, a   end
        end
    end
    return false, nil
end

local function _setUpval(fn, i, newVal)
    if debug and debug.setupvalue then
        pcall(debug.setupvalue, fn, i, newVal)
    end
    if setupvalue then
        pcall(setupvalue, fn, i, newVal)
    end
end

-- ============================================================
-- _extractOrigIndex(fn):
--   Scans all upvalues of fn looking for the first function
--   value — that is aresontop's saved `oldIndex` (the real
--   Roblox __index before any hooks).  Supports getupvalues
--   (table return), debug.getupvalue, and global getupvalue.
-- ============================================================
local function _extractOrigIndex(fn)
    if not fn then return nil end

    -- Method 1: getupvalues() → returns table {[i] = value, …}
    if getupvalues then
        local ok, uvs = pcall(getupvalues, fn)
        if ok and type(uvs) == "table" then
            for _, v in pairs(uvs) do
                if type(v) == "function" then return v end
            end
        end
    end

    -- Method 2: index-based scan via _getUpval
    for i = 1, 200 do
        local found, val = _getUpval(fn, i)
        if not found then break end
        if type(val) == "function" then return val end
    end

    return nil
end

-- ============================================================
-- _neutralizeHook(fn):
--   Sets every boolean upvalue in fn that is currently TRUE
--   to FALSE.  This targets aresontop's `hackEnabled` flag
--   directly, disabling the spoof at its source regardless
--   of what name or index it lives at.
-- ============================================================
local function _neutralizeHook(fn)
    if not fn then return end

    -- Method 1: getupvalues + setupvalues (table API)
    if getupvalues and setupvalues then
        local ok, uvs = pcall(getupvalues, fn)
        if ok and type(uvs) == "table" then
            local patch = {}
            for k, v in pairs(uvs) do
                if type(v) == "boolean" then patch[k] = false end
            end
            pcall(setupvalues, fn, patch)
        end
    end

    -- Method 2: index-based scan + _setUpval
    for i = 1, 200 do
        local found, val = _getUpval(fn, i)
        if not found then break end
        if type(val) == "boolean" then
            _setUpval(fn, i, false)
        end
    end
end

-- ============================================================
-- Attempt to extract the original Roblox __index IMMEDIATELY,
-- before any other code runs.  If aresontop is already hooked,
-- _origIndex will be the real Roblox __index that lives in
-- aresontop's `oldIndex` upvalue.
-- ============================================================
local _origIndex = nil

pcall(function()
    local mt  = getrawmetatable(game)
    local idx = rawget(mt, "__index")
    if type(idx) == "function" then
        local orig = _extractOrigIndex(idx)
        -- Sanity-check: real Roblox __index can read game.PlaceId (a number)
        if orig then
            local ok, testVal = pcall(orig, game, "PlaceId")
            if ok and type(testVal) == "number" then
                _origIndex = orig
            end
        end
    end
end)

-- ============================================================
-- _readReal(prop):
--   Reads a property from LocalPlayer bypassing any active
--   __index hook.  Tries four independent methods in order:
--
--   A) cloneref  — cloneref(LP) ~= LP in Lua identity, so
--      aresontop's  "t == LocalPlayer"  guard never fires.
--      The call falls through to the original Roblox __index
--      which returns the true value.
--
--   B) _origIndex direct call  — calls the real Roblox __index
--      extracted from aresontop's upvalues, completely skipping
--      the hook wrapper.
--
--   C) GetFullName() C++ path  — Name-only fallback.
--
--   D) Raw read  — last resort, may return spoofed value.
-- ============================================================
local function _readReal(prop)
    -- A) cloneref bypass
    if cloneref then
        local ok, val = pcall(function()
            return cloneref(LocalPlayer)[prop]
        end)
        if ok and val ~= nil then return val end
    end

    -- B) Original __index direct call
    if _origIndex then
        local ok, val = pcall(_origIndex, LocalPlayer, prop)
        if ok and val ~= nil then return val end
    end

    -- C) GetFullName C++ path (Name only)
    if prop == "Name" then
        local ok, val = pcall(function()
            return LocalPlayer:GetFullName():match("Players%.(.+)")
        end)
        if ok and val and val ~= "" then return val end
    end

    -- D) Raw read fallback (may be hooked — last resort only)
    local ok, val = pcall(function() return LocalPlayer[prop] end)
    if ok then return val end
    return nil
end

-- ============================================================
-- Initial identity capture using hook-bypass reader
-- ============================================================
local RealName        = tostring(_readReal("Name") or "")
local RealDisplayName = tostring(_readReal("DisplayName") or RealName)
local RealUserId      = _readReal("UserId")

-- Reinforce RealName with GetFullName C++ path
pcall(function()
    local n = LocalPlayer:GetFullName():match("Players%.(.+)")
    if n and n ~= "" then RealName = n end
end)

-- Detect whether the __index hook is currently spoofing our Name
local _hookedName = ""
pcall(function() _hookedName = tostring(LocalPlayer.Name) end)
local _nameHooked = (_hookedName ~= RealName)

-- If name is spoofed, DisplayName from __index is also spoofed
if _nameHooked then
    RealDisplayName = RealName
end

-- ============================================================
-- Async identity verification:
--   Uses Players:GetUserIdFromNameAsync — a METHOD CALL that
--   never touches __index at all.  Even if every property read
--   on LocalPlayer is hooked, this returns the true UserId
--   directly from Roblox's servers.  Runs once on startup.
-- ============================================================
task.spawn(function()
    pcall(function()
        -- GetUserIdFromNameAsync is 100% __index-immune (method, not property)
        local ok, uid = pcall(function()
            return Players:GetUserIdFromNameAsync(RealName)
        end)
        if ok and type(uid) == "number" and uid > 0 then
            RealUserId = uid
        end

        -- Re-verify DisplayName now that we have a confirmed RealName
        if not _nameHooked then
            local dn = tostring(_readReal("DisplayName") or "")
            if dn ~= "" then RealDisplayName = dn end
        end

        -- Ban re-check after UserId is confirmed
        if BANNED_IDS and BANNED_IDS[RealUserId] then
            isKickedOrBanned = true
            LocalPlayer:Kick("You are permanently banned from Ares Chat.")
        end
    end)
end)

-- ============================================================
-- Hook neutralisation:
--   Disable aresontop's hackEnabled flag by zeroing every
--   boolean upvalue in the hooked __index.  Runs immediately
--   in a task.spawn so it doesn't delay chat startup.
-- ============================================================
task.spawn(function()
    pcall(function()
        local mt  = getrawmetatable(game)
        if not mt then return end
        local idx = rawget(mt, "__index")
        if type(idx) ~= "function" then return end
        _neutralizeHook(idx)
    end)
end)

-- ============================================================
-- Continuous integrity guard — runs every 5 seconds.
-- Refreshes all three real-identity variables and re-neutralises
-- the hook in case aresontop is injected AFTER areschat starts
-- or hackEnabled is re-enabled by user interaction.
-- ============================================================
task.spawn(function()
    while task.wait(5) do
        pcall(function()
            -- Refresh _origIndex in case hook changed
            local mt  = getrawmetatable(game)
            if mt then
                local idx = rawget(mt, "__index")
                if type(idx) == "function" then
                    -- Re-neutralise hackEnabled every cycle
                    _neutralizeHook(idx)
                    -- Re-extract original __index
                    local orig = _extractOrigIndex(idx)
                    if orig then
                        local ok, testVal = pcall(orig, game, "PlaceId")
                        if ok and type(testVal) == "number" then
                            _origIndex = orig
                        end
                    end
                end
            end

            -- Refresh RealName via C++ path (hook-immune)
            local fp = LocalPlayer:GetFullName()
            local fn = fp and fp:match("Players%.(.+)")
            if fn and fn ~= "" then RealName = fn end

            -- Refresh RealUserId via bypass reader
            local freshUid = _readReal("UserId")
            if freshUid and type(freshUid) == "number" and freshUid > 0 then
                RealUserId = freshUid
            end

            -- Detect hook state and refresh DisplayName safely
            local luaName = ""
            pcall(function() luaName = tostring(LocalPlayer.Name) end)
            if luaName ~= RealName then
                -- Hook is active: DisplayName through __index is spoofed
                RealDisplayName = RealName
            else
                local dn = tostring(_readReal("DisplayName") or "")
                if dn ~= "" then RealDisplayName = dn end
            end
        end)
    end
end)

-- CONFIGURATION
local DATABASE_URL        = "https://ares-rechat-2-default-rtdb.firebaseio.com/chat"
local ONLINE_URL          = "https://ares-rechat-2-default-rtdb.firebaseio.com/online"
local UNSENT_URL          = "https://ares-rechat-2-default-rtdb.firebaseio.com/unsent"
local BAN_URL             = "https://ares-rechat-2-default-rtdb.firebaseio.com/bans"
local CUSTOM_TITLES_URL   = "https://ares-rechat-2-default-rtdb.firebaseio.com/custom_titles"
local MUSIC_SYNC_URL      = "https://ares-rechat-2-default-rtdb.firebaseio.com/music_server"
local FOLLOWERS_URL       = "https://ares-rechat-2-default-rtdb.firebaseio.com/followers"
local PROFILES_URL        = "https://ares-rechat-2-default-rtdb.firebaseio.com/profiles"
local STICKER_IDS_URL     = "https://raw.githubusercontent.com/Goku55050/Ares-roblox/refs/heads/main/stickers.json"
local TROPHIES_URL        = "https://ares-rechat-2-default-rtdb.firebaseio.com/trophies"
local GAMEBOT_URL         = "https://ares-rechat-2-default-rtdb.firebaseio.com/gamebot"

-- TITLES CONFIGURATION
local CREATOR_ID = 5153861463
local OWNER_ID   = 8515976898

local CUTE_IDS = {
}

local HELLGOD_IDS = {
    [4713811292] = true
}

local VIP_IDS = {
    [10415627505] = true,
}

-- GOD tag — black colour (non-RGB)
local GOD_IDS = {
    [0] = true,
}

-- DADDY — RGB title
local DADDY_IDS = {
    [6027243763] = true
}

-- REAPER — RGB title (replace 0 with the real UserId)
local REAPER_IDS = {
    [0] = true   -- ← put the UserId here
}

-- PAPA MVP — RGB title (replace 0 with the real UserId)
local PAPA_MVP_IDS = {
    [7534011806] = true,
}

-- PERMANENT BAN LIST
local BANNED_IDS = {
    [10497392350] = true
}

-- BAN CHECK ON STARTUP
if BANNED_IDS[RealUserId] then
    LocalPlayer:Kick("You are permanently banned from Ares Chat.")
    return
end

-- ============================================================
-- CUSTOM TITLES TABLE (loaded from Firebase)
-- Key: userId (number), Value: {title = string, expiresAt = number}
-- Creator-only: /title [name] [text] and /untitle [name]
-- ============================================================
local CustomTitles = {}

-- Load custom titles from Firebase on startup
task.spawn(function()
    task.wait(2)
    pcall(function()
        local req = syn and syn.request or http and http.request or request
        if not req then return end
        local res = req({Url = CUSTOM_TITLES_URL .. ".json", Method = "GET"})
        if res and res.Success and res.Body ~= "null" then
            local ok, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
            if ok and type(data) == "table" then
                local now = os.time()
                for uidStr, entry in pairs(data) do
                    local uid = tonumber(uidStr)
                    if uid and type(entry) == "table" then
                        -- Only load non-expired titles (1 day = 86400 seconds)
                        if entry.expiresAt and (entry.expiresAt > now) then
                            CustomTitles[uid] = {title = entry.title, expiresAt = entry.expiresAt, color = entry.color}
                        end
                    end
                end
            end
        end
    end)
end)

-- CACHE TABLES
local TagCache = {}
local SpecialLabels = {}
local NormalTitleLabels = {}  -- [label] = data — Normal-tag users with follower titles
local processedKeys = {}
local activeNotification = nil

-- SCRIPT USERS REGISTRY
local scriptUsersInServer = {}

-- PRIVATE CHAT & REPLY STATE
local PrivateTargetName = nil
local PrivateTargetId = nil
local ReplyTargetName = nil
local ReplyTargetMsg = nil
local ActivePageName = "Chat"

-- FEATURE STATES
local Flying = false
local Noclip = false
local IsInvisible = false

-- ============================================================
-- MUTED PLAYERS TABLE
-- Populated by /mute and /unmute commands.
-- LOCAL MUTE: only affects the local player's view.
-- Checked in addMessage() and createBubble() to suppress output.
-- ============================================================
local MutedPlayers = {}

-- Forward declaration so sticker callbacks (defined before send()) can call it
local send

-- ============================================================
-- KICKED / BANNED FLAG
-- Set to true immediately before LocalPlayer:Kick() so that
-- no further messages can be sent in the brief window before
-- the player is actually removed from the game.
-- ============================================================
local isKickedOrBanned = false

-- ============================================================
-- EDIT MODE — tracks the Firebase key of the message currently
-- being edited.  When non-nil, the next send() call patches
-- that message in-place instead of posting a new one.
-- ============================================================
local editingKey = nil

-- ============================================================
-- GAMEBOT STATE
-- gameBotIsHost  = true only on the client that typed /gamebot.
-- Only the host generates questions, checks answers, awards trophies.
-- All clients see questions/winner messages via normal Firebase sync.
-- ============================================================
local gameBotActive     = false
local gameBotIsHost     = false
local gameBotGame       = nil    -- "math" | "unscramble" | "guess" | "fill"
local gameBotRound      = 0
local gameBotTotal      = 10
local gameBotAnswer     = nil    -- expected answer (lowercase string)
local gameBotWinCounts  = {}     -- [displayName] = wins this session
local gameBotWinnerUids = {}     -- [displayName] = uid  (for trophy award at end)
local gameBotPending    = false  -- waiting for user to pick a game (1-4)
local trophyCache       = {}     -- [uid] = all-time trophy count

-- ============================================================
-- TITLE SYSTEM — follower-count-based titles (text, RGB animated)
-- 100+ followers → [VIP]     — smooth RGB yellow shades   (top priority)
--  50+ followers → [Legend]    — smooth RGB red shades
--  10+ followers → [Premium] — smooth RGB blue shades (dark→light blue)
-- Titles are prefixes in chat/profile and suffixes in leaderboard.
-- Ignored if user already has a hardcoded or custom /title.
-- ============================================================
local badgeCache = {}            -- [uid] = follower count (number); nil = not loaded; -1 = pending
local badgeUpdateCallbacks = {}  -- [uid] = list of callback functions to call once badge loads

-- Returns the follower-title type string for a given count, or nil if none.
-- Priority order: VIP (100+) > Legend (50+) > Premium (10+)
local function getFollowerTitleTypeFromCount(count)
    if not count or count < 0 then return nil end
    if count >= 100 then
        return "VIP"
    elseif count >= 50 then
        return "Legend"
    elseif count >= 10 then
        return "Premium"
    end
    return nil
end

-- Returns the follower-title type for a uid (from cache).
local function getFollowerTitleType(uid)
    return getFollowerTitleTypeFromCount(badgeCache[uid])
end

-- Returns the plain-text title prefix string (e.g. "[Premium] ") for rendering,
-- or "" if none. Used in static/initial renders before the RGB loop takes over.
local function getFollowerTitle(uid)
    local t = getFollowerTitleType(uid)
    if t then return "[" .. t .. "] " end
    return ""
end

-- Returns the plain-text title prefix from a count (for join message).
local function getFollowerTitleFromCount(count)
    local t = getFollowerTitleTypeFromCount(count)
    if t then return " [" .. t .. "]" end
    return ""
end

-- Fetches follower count for uid asynchronously, fires callbacks when done.
local function fetchBadgeAsync(uid)
    if not uid or uid == 0 then return end
    if badgeCache[uid] ~= nil then return end
    badgeCache[uid] = -1  -- pending
    task.spawn(function()
        pcall(function()
            local req = syn and syn.request or http and http.request or request
            if not req then badgeCache[uid] = 0 return end
            local res = req({ Url = FOLLOWERS_URL .. "/" .. tostring(uid) .. ".json", Method = "GET" })
            local count = 0
            if res and res.Success and res.Body ~= "null" then
                local ok, fdata = pcall(HttpService.JSONDecode, HttpService, res.Body)
                if ok and type(fdata) == "table" then
                    for _ in pairs(fdata) do count = count + 1 end
                end
            end
            badgeCache[uid] = count
            followerCountCache[uid] = count
            -- Fire pending callbacks
            local cbs = badgeUpdateCallbacks[uid]
            if cbs then
                badgeUpdateCallbacks[uid] = nil
                for _, cb in ipairs(cbs) do pcall(cb) end
            end
        end)
    end)
end

local function onBadgeLoaded(uid, callback)
    if uid and uid ~= 0 then
        if badgeCache[uid] and badgeCache[uid] >= 0 then
            task.spawn(callback)
        else
            if not badgeUpdateCallbacks[uid] then badgeUpdateCallbacks[uid] = {} end
            table.insert(badgeUpdateCallbacks[uid], callback)
            fetchBadgeAsync(uid)
        end
    end
end

-- ============================================================
-- LOCAL ORDER COUNTER — ensures local-only system messages
-- (order=0 calls) appear at the BOTTOM of the chat log.
-- Firebase keys use 12-digit timestamp + 3-digit suffix (max 999).
-- We use timestamp*1000 + 999 + counter so local messages
-- always sort AFTER Firebase messages from the same second.
-- ============================================================
local _localOrderCount = 0
local function nextLocalOrder()
    _localOrderCount = _localOrderCount + 1
    return os.time() * 1000 + 999 + _localOrderCount
end

-- ============================================================
-- ANTI-SPAM CONFIG
-- ============================================================
local MAX_CHAR_LIMIT    = 200   -- maximum characters per message
local SPAM_INTERVAL     = 2.0   -- minimum seconds between messages
local SPAM_MAX          = 5     -- max messages allowed in SPAM_WINDOW seconds
local SPAM_WINDOW       = 8     -- rolling window length (seconds)
local _lastSentTime     = 0
local _lastSentMsg      = ""
local _spamCount        = 0
local _spamWindowStart  = os.time()

-- MAX MESSAGES IN CHAT (memory management)
local MAX_MESSAGES = 20

-- IDLE AUTO-CLEAR: track last message time for the 10-min idle wipe
local lastMessageTime = os.time()
local IDLE_CLEAR_SECONDS = 600  -- 10 minutes

-- ============================================================
-- ORDERED KEY TRACKING for correct oldest-first trimming
-- sortedMessageKeys holds Firebase keys in ascending order
-- so we always know exactly which key is oldest.
-- ============================================================
local sortedMessageKeys = {}   -- list of Firebase key strings, ascending order
local keyToButton = {}         -- Firebase key string → UI TextButton












-- FUNCTION TO FIND PLAYER BY NAME
local function GetPlayerByName(name)
    name = string.lower(name)
    for _, p in pairs(Players:GetPlayers()) do
        if string.find(string.lower(p.Name), name) or string.find(string.lower(p.DisplayName), name) then
            return p
        end
    end
    return nil
end

-- FUNCTION TO CHECK TAGS
local function CachePlayerTags(player)
    if not player then return end
    if TagCache[player.UserId] then return TagCache[player.UserId] end
    local tagData = {text = "", type = "Normal", tagTitle = nil}
    if player.UserId == CREATOR_ID then
        tagData.text     = "[ᴄʀᴇᴀᴛᴏʀ] "
        tagData.type     = "Creator"
        tagData.tagTitle = "[ᴄʀᴇᴀᴛᴏʀ]"
    elseif player.UserId == OWNER_ID then
        tagData.text     = "[SUPREME] "
        tagData.type     = "Owner"
        tagData.tagTitle = "[SUPREME]"
    elseif CUTE_IDS[player.UserId] then
        tagData.text = "[CUTE] "
        tagData.type = "Cute"
    elseif HELLGOD_IDS[player.UserId] then
        tagData.text     = "[HellGod] "
        tagData.type     = "HellGod"
        tagData.tagTitle = "[HellGod]"
    elseif GOD_IDS[player.UserId] then
        tagData.text     = "[GOD] "
        tagData.type     = "God"
        tagData.tagTitle = "[GOD]"
    elseif DADDY_IDS[player.UserId] then
        tagData.text     = "[DADDY] "
        tagData.type     = "Daddy"
        tagData.tagTitle = "[DADDY]"
    elseif REAPER_IDS[player.UserId] then
        tagData.text     = "[REAPER] "
        tagData.type     = "Reaper"
        tagData.tagTitle = "[REAPER]"
    elseif PAPA_MVP_IDS[player.UserId] then
        tagData.text     = "[PAPA MVP] "
        tagData.type     = "PapaMvp"
        tagData.tagTitle = "[PAPA MVP]"
    elseif VIP_IDS[player.UserId] then
        tagData.text = "[VIP] "
        tagData.type = "Vip"
    end
    -- Custom titles override (checked after built-in titles only for non-special users)
    -- Custom titles are only applied if the user has no other special tag
    if tagData.type == "Normal" then
        local ct = CustomTitles[player.UserId]
        if ct then
            local now = os.time()
            if ct.expiresAt and ct.expiresAt > now then
                tagData.text     = "[" .. ct.title .. "] "
                tagData.type     = "CustomTitle"
                tagData.tagTitle = "[" .. ct.title .. "]"
            else
                -- Expired — remove from local cache
                CustomTitles[player.UserId] = nil
            end
        end
    end
    TagCache[player.UserId] = tagData
    return tagData
end

-- ============================================================
-- CRITICAL FIX: RGB LOOP WITH STRICT SAFE TEXT ENCODING
-- NOTE: replyTo is now rendered as a separate sub-frame inside
-- the TextButton (created in addMessage), so we do NOT include
-- it here — this prevents the reply text from overlapping.
--
-- TAG COLOR RULES:
--   GOD        → silver (rgb(192,192,192)) — non-RGB, static silver
--   CustomTitle → red (rgb(220,50,50)) — non-RGB, static red
--   DADDY      → RGB cycling (same as Creator/Owner/HellGod)
--   All others with special tags → RGB cycling
-- ============================================================
local function SafeEncodeMsg(raw)
    raw = tostring(raw or "")
    raw = raw:gsub("<[^>]*>", "")
    return raw
end

-- ============================================================
-- FOLLOWER TITLE RGB COLOR HELPERS
-- VIP     (100+): smooth yellow shade RGB cycle  (top priority)
-- Legend     (50+): smooth red shade RGB cycle
-- Premium  (10+): smooth dark-to-light blue RGB cycle
-- All run at ~10 fps (0.1s throttle) — lag-free.
-- ============================================================
local function getFollowerTitleRgbString(titleType, now)
    -- Simple static colours (no RGB animation)
    if titleType == "VIP" then
        -- Simple static gold/yellow
        return "rgb(220,180,0)"
    elseif titleType == "Legend" then
        -- Simple static red
        return "rgb(220,50,50)"
    elseif titleType == "Premium" then
        -- Simple static light blue
        return "rgb(100,185,255)"
    end
    return nil
end

-- Throttle RGB label updates to ~10 fps (was 60 fps — primary lag source)
local _lastRgbTick = 0
RunService.Heartbeat:Connect(function()
    local now = tick()
    if now - _lastRgbTick < 0.1 then return end
    _lastRgbTick = now

    local hue = (now % 5) / 5
    local color = Color3.fromHSV(hue, 1, 1)
    local r = math.clamp(math.floor(color.R * 255), 0, 255)
    local g = math.clamp(math.floor(color.G * 255), 0, 255)
    local b = math.clamp(math.floor(color.B * 255), 0, 255)
    local rgbString = "rgb(" .. r .. "," .. g .. "," .. b .. ")"

    for label, data in pairs(SpecialLabels) do
        if label and label.Parent then
            local pvtPart  = data.isPrivate and "<font color='rgb(255,100,255)'>[PVT] </font>" or ""
            local tagTitle = data.tagTitle or ("[" .. data.tagType:upper() .. "]")
            local safeMsg  = SafeEncodeMsg(data.msg)

            -- Build formatted text string
            -- (SpecialLabels only contains non-Normal tag users; follower titles never apply here)
            local fmtText
            if data.tagType == "God" then
                fmtText = string.format(
                    "%s<font color='rgb(192,192,192)'><b>%s</b></font> <font color='%s'><b>%s</b></font>: %s",
                    pvtPart, tagTitle, data.nameColor, data.displayName, safeMsg)
            elseif data.tagType == "CustomTitle" then
                local ctColor = data.titleColor or "rgb(220,50,50)"
                fmtText = string.format(
                    "%s<font color='%s'><b>%s</b></font> <font color='%s'><b>%s</b></font>: %s",
                    pvtPart, ctColor, tagTitle, data.nameColor, data.displayName, safeMsg)
            else
                fmtText = string.format(
                    "%s<font color='%s'><b>%s</b></font> <font color='%s'><b>%s</b></font>: %s",
                    pvtPart, rgbString, tagTitle, data.nameColor, data.displayName, safeMsg)
            end
            -- STICKER special-tag: update the separate nameLabel child, not the button text
            if data.isSticker and data.stickerLabel and data.stickerLabel.Parent then
                data.stickerLabel.RichText = true
                -- For sticker bubbles only show name (no ": msg" suffix)
                local nameFmt
                if data.tagType == "God" then
                    nameFmt = string.format(
                        "%s<font color='rgb(192,192,192)'><b>%s</b></font> <font color='%s'><b>%s</b></font>",
                        pvtPart, tagTitle, data.nameColor, data.displayName)
                elseif data.tagType == "CustomTitle" then
                    local ctColor = data.titleColor or "rgb(220,50,50)"
                    nameFmt = string.format(
                        "%s<font color='%s'><b>%s</b></font> <font color='%s'><b>%s</b></font>",
                        pvtPart, ctColor, tagTitle, data.nameColor, data.displayName)
                else
                    nameFmt = string.format(
                        "%s<font color='%s'><b>%s</b></font> <font color='%s'><b>%s</b></font>",
                        pvtPart, rgbString, tagTitle, data.nameColor, data.displayName)
                end
                data.stickerLabel.Text = nameFmt
            else
                label.RichText = true
                label.Text = fmtText
            end
        else
            SpecialLabels[label] = nil
        end
    end

    -- Update NormalTitle labels (follower titles for Normal-tag users only)
    for label, data in pairs(NormalTitleLabels) do
        if label and label.Parent then
            local fTitleType = getFollowerTitleType(data.senderUid)
            if fTitleType then
                local fColor = getFollowerTitleRgbString(fTitleType, now)
                local pvtPart = data.isPrivate and "<font color='rgb(255,100,255)'>[PVT] </font>" or ""
                local safeMsg = SafeEncodeMsg(data.msg)
                label.RichText = true
                if data.isSticker and data.stickerLabel and data.stickerLabel.Parent then
                    data.stickerLabel.RichText = true
                    data.stickerLabel.Text = string.format(
                        "%s<font color='%s'><b>[%s]</b></font> <font color='%s'><b>%s</b></font>",
                        pvtPart, fColor, fTitleType, data.nameColor, data.displayName)
                else
                    label.Text = string.format(
                        "%s<font color='%s'><b>[%s]</b></font> <font color='%s'><b>%s</b></font>: %s",
                        pvtPart, fColor, fTitleType, data.nameColor, data.displayName, safeMsg)
                end
            end
        else
            NormalTitleLabels[label] = nil
        end
    end
end)

for _, p in pairs(Players:GetPlayers()) do task.spawn(CachePlayerTags, p) end
Players.PlayerAdded:Connect(CachePlayerTags)

-- ============================================================
-- PREMIUM UI SETUP
-- ============================================================
local ScreenGui = Instance.new("ScreenGui", game:GetService("CoreGui"))
ScreenGui.Name = "AresChat_Universal_V8"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- NOTIFICATION CONTAINER — top-center, slides down
local NotifContainer = Instance.new("Frame", ScreenGui)
NotifContainer.Size = UDim2.new(0, 310, 0, 80)
NotifContainer.Position = UDim2.new(0.5, 0, 0, -10)
NotifContainer.AnchorPoint = Vector2.new(0.5, 0)
NotifContainer.BackgroundTransparency = 1
NotifContainer.ClipsDescendants = true

-- MAIN FRAME
local Main = Instance.new("Frame", ScreenGui)
Main.Size = UDim2.new(0, 374, 0, 330)
Main.Position = UDim2.new(0.5, 0, 0.4, 0)
Main.AnchorPoint = Vector2.new(0.5, 0.5)
Main.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
Main.BackgroundTransparency = 0
Main.BorderSizePixel = 0
Main.Active = true
local MainCorner = Instance.new("UICorner", Main)
MainCorner.CornerRadius = UDim.new(0, 16)

-- Outer glow border effect
local MainStroke = Instance.new("UIStroke", Main)
MainStroke.Color = Color3.fromRGB(225, 48, 108)
MainStroke.Thickness = 1.5
MainStroke.Transparency = 0.0

-- Static pink border (Instagram pink theme)
task.spawn(function()
    while Main and Main.Parent do
        MainStroke.Color = Color3.fromRGB(225, 48, 108)
        task.wait(1)
    end
end)

-- HEADER
local Header = Instance.new("Frame", Main)
Header.Size = UDim2.new(1, 0, 0, 38)
Header.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
Header.BackgroundTransparency = 0
Header.BorderSizePixel = 0
local HeaderCorner = Instance.new("UICorner", Header)
HeaderCorner.CornerRadius = UDim.new(0, 16)
local HeaderFix = Instance.new("Frame", Header)
HeaderFix.Size = UDim2.new(1, 0, 0.5, 0)
HeaderFix.Position = UDim2.new(0, 0, 0.5, 0)
HeaderFix.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
HeaderFix.BackgroundTransparency = 0
HeaderFix.BorderSizePixel = 0

-- Header bottom border line (Instagram divider style)
local HeaderDivider = Instance.new("Frame", Header)
HeaderDivider.Size = UDim2.new(1, 0, 0, 1)
HeaderDivider.Position = UDim2.new(0, 0, 1, -1)
HeaderDivider.BackgroundColor3 = Color3.fromRGB(219, 219, 219)
HeaderDivider.BackgroundTransparency = 0
HeaderDivider.BorderSizePixel = 0

-- Logo dot
local LogoDot = Instance.new("Frame", Header)
LogoDot.Size = UDim2.new(0, 8, 0, 8)
LogoDot.Position = UDim2.new(0, 10, 0.5, -4)
LogoDot.BackgroundColor3 = Color3.fromRGB(225, 48, 108)
LogoDot.BorderSizePixel = 0
Instance.new("UICorner", LogoDot).CornerRadius = UDim.new(1, 0)

local Title = Instance.new("TextLabel", Header)
Title.Size = UDim2.new(1, -40, 1, 0)
Title.Position = UDim2.new(0, 24, 0, 0)
Title.Text = "* ARES RECHAT - V39🐥"
Title.TextColor3 = Color3.fromRGB(0, 0, 0)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Font = Enum.Font.GothamBold
Title.TextSize = 13
Title.BackgroundTransparency = 1
Title.ZIndex = 2

-- ============================================================
-- THEME SYSTEM — light (default) / dark toggle
-- ============================================================
local isDarkTheme = false
local THEME = {
    light = {
        mainBg       = Color3.fromRGB(255, 255, 255),
        headerBg     = Color3.fromRGB(255, 255, 255),
        headerFixBg  = Color3.fromRGB(255, 255, 255),
        divider      = Color3.fromRGB(219, 219, 219),
        inputBg      = Color3.fromRGB(250, 250, 250),
        inputStroke  = Color3.fromRGB(219, 219, 219),
        titleColor   = Color3.fromRGB(0, 0, 0),
        btnBg        = Color3.fromRGB(239, 239, 239),
        btnText      = Color3.fromRGB(50, 50, 50),
    },
    dark = {
        mainBg       = Color3.fromRGB(18, 18, 18),
        headerBg     = Color3.fromRGB(25, 25, 25),
        headerFixBg  = Color3.fromRGB(25, 25, 25),
        divider      = Color3.fromRGB(60, 60, 60),
        inputBg      = Color3.fromRGB(30, 30, 30),
        inputStroke  = Color3.fromRGB(60, 60, 60),
        titleColor   = Color3.fromRGB(255, 255, 255),
        btnBg        = Color3.fromRGB(40, 40, 40),
        btnText      = Color3.fromRGB(220, 220, 220),
    }
}
local function applyTheme(dark)
    local t = dark and THEME.dark or THEME.light
    Main.BackgroundColor3 = t.mainBg
    Header.BackgroundColor3 = t.headerBg
    HeaderFix.BackgroundColor3 = t.headerFixBg
    HeaderDivider.BackgroundColor3 = t.divider
    Title.TextColor3 = t.titleColor
    -- InputArea and InputStroke updated via pcall (defined later in code)
    pcall(function() InputArea.BackgroundColor3 = t.inputBg end)
    pcall(function() InputStroke.Color = t.inputStroke end)
    -- Update lock/theme button backgrounds
    LockBtn.BackgroundColor3 = t.btnBg
    LockBtn.TextColor3 = t.btnText
end

-- ============================================================
-- LOCK BUTTON — next to Minimize, toggles GUI drag lock.
-- When LOCKED: GUI cannot be dragged at all.
-- When UNLOCKED: GUI drags normally via header.
-- The LockBtn itself is always non-draggable.
-- ============================================================
local isGuiLocked = false

local LockBtn = Instance.new("TextButton", Header)
LockBtn.Size = UDim2.new(0, 26, 0, 26)
LockBtn.Position = UDim2.new(1, -92, 0.5, -13)
LockBtn.Text = "🔓"
LockBtn.Font = Enum.Font.GothamBold
LockBtn.TextColor3 = Color3.fromRGB(50, 50, 50)
LockBtn.BackgroundColor3 = Color3.fromRGB(239, 239, 239)
LockBtn.BackgroundTransparency = 0.0
LockBtn.TextSize = 13
LockBtn.ZIndex = 3
Instance.new("UICorner", LockBtn).CornerRadius = UDim.new(1, 0)

LockBtn.MouseButton1Click:Connect(function()
    isGuiLocked = not isGuiLocked
    if isGuiLocked then
        LockBtn.Text = "🔒"
        LockBtn.BackgroundColor3 = Color3.fromRGB(255, 220, 220)
        LockBtn.TextColor3 = Color3.fromRGB(200, 50, 50)
    else
        LockBtn.Text = "🔓"
        LockBtn.BackgroundColor3 = Color3.fromRGB(239, 239, 239)
        LockBtn.TextColor3 = Color3.fromRGB(50, 50, 50)
    end
end)

-- ============================================================
-- THEME BUTTON — sits to the left of LockBtn.
-- 🌙 = switch to dark theme  |  ☀️ = switch to light theme
-- Default: light theme (☀️ icon shows to switch to dark)
-- ============================================================
local ThemeBtn = Instance.new("TextButton", Header)
ThemeBtn.Size = UDim2.new(0, 26, 0, 26)
ThemeBtn.Position = UDim2.new(1, -122, 0.5, -13)
ThemeBtn.Text = "🌙"
ThemeBtn.Font = Enum.Font.GothamBold
ThemeBtn.TextColor3 = Color3.fromRGB(50, 50, 50)
ThemeBtn.BackgroundColor3 = Color3.fromRGB(239, 239, 239)
ThemeBtn.BackgroundTransparency = 0.0
ThemeBtn.TextSize = 13
ThemeBtn.ZIndex = 3
Instance.new("UICorner", ThemeBtn).CornerRadius = UDim.new(1, 0)

ThemeBtn.MouseButton1Click:Connect(function()
    isDarkTheme = not isDarkTheme
    if isDarkTheme then
        ThemeBtn.Text = "☀️"
        ThemeBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
        ThemeBtn.TextColor3 = Color3.fromRGB(255, 240, 100)
    else
        ThemeBtn.Text = "🌙"
        ThemeBtn.BackgroundColor3 = Color3.fromRGB(239, 239, 239)
        ThemeBtn.TextColor3 = Color3.fromRGB(50, 50, 50)
    end
    applyTheme(isDarkTheme)
end)

-- ============================================================
-- STICKER BUTTON — sits between Lock and Minimize buttons.
-- Tapping opens a small floating sticker panel above the header.
-- Clicking any sticker instantly sends it to Firebase as a
-- [STICKER:assetId] message visible to all script users.
-- ============================================================
-- STICKER_IDS — fetched from GitHub at startup so obfuscation never
-- corrupts the asset ID numbers.  Empty until the fetch completes
-- (typically < 1 second); the panel is safe to open after that.
local STICKER_IDS = {}
local _stickersLoaded = false

task.spawn(function()
    pcall(function()
        local req = syn and syn.request or http and http.request or request
        if not req then return end
        local res = req({ Url = STICKER_IDS_URL, Method = "GET" })
        if res and res.Success and res.Body and res.Body ~= "" then
            local ok, decoded = pcall(HttpService.JSONDecode, HttpService, res.Body)
            if ok and type(decoded) == "table" then
                for _, id in ipairs(decoded) do
                    table.insert(STICKER_IDS, id)
                end
            end
        end
    end)
    _stickersLoaded = true
end)

local stickerPanelOpen = false
local StickerPanel = nil
local lastStickerScrollX = 0  -- remember horizontal scroll position

-- StickerBtn is created AFTER InputArea is defined (below), stored here for forward reference
local StickerBtn

local function closeStickerPanel()
    if StickerPanel and StickerPanel.Parent then
        -- Save scroll position before closing
        local scrollChild = StickerPanel:FindFirstChildOfClass("ScrollingFrame")
        if scrollChild then lastStickerScrollX = scrollChild.CanvasPosition.X end
        TweenService:Create(StickerPanel, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            {BackgroundTransparency = 1}):Play()
        task.delay(0.16, function()
            if StickerPanel and StickerPanel.Parent then
                StickerPanel:Destroy()
                StickerPanel = nil
            end
        end)
    end
    stickerPanelOpen = false
    if StickerBtn then StickerBtn.BackgroundColor3 = Color3.fromRGB(239, 239, 239) end
end

local function openStickerPanel()
    if StickerPanel and StickerPanel.Parent then closeStickerPanel() return end
    -- If stickers haven't loaded yet from GitHub, wait up to 3 seconds then retry
    if not _stickersLoaded then
        task.spawn(function()
            local waited = 0
            while not _stickersLoaded and waited < 3 do
                task.wait(0.1)
                waited = waited + 0.1
            end
            openStickerPanel()
        end)
        return
    end
    stickerPanelOpen = true
    if StickerBtn then StickerBtn.BackgroundColor3 = Color3.fromRGB(225, 48, 108) end

    -- Panel container — floating just above the input area, full-width premium style
    local panel = Instance.new("Frame", ScreenGui)
    panel.Name = "AresStickerPanel"
    panel.Size = UDim2.new(0, 320, 0, 130)
    panel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    panel.BackgroundTransparency = 0.0
    panel.BorderSizePixel = 0
    panel.ZIndex = 300
    panel.ClipsDescendants = true

    local panelCorner = Instance.new("UICorner", panel)
    panelCorner.CornerRadius = UDim.new(0, 14)
    local panelStroke = Instance.new("UIStroke", panel)
    panelStroke.Color = Color3.fromRGB(225, 48, 108)
    panelStroke.Thickness = 1.3
    panelStroke.Transparency = 0.0

    -- Position the panel just above the input area (bottom of chat window)
    local absPos  = Main.AbsolutePosition
    local absSize = Main.AbsoluteSize
    local vpSize  = game.Workspace.CurrentCamera.ViewportSize
    local px = absPos.X
    local py = absPos.Y + absSize.Y - 44 - 130 - 4  -- above input area
    px = math.clamp(px, 4, vpSize.X - 324)
    py = math.clamp(py, 4, vpSize.Y - 135)
    panel.Position = UDim2.new(0, px, 0, py)

    -- Scrolling inner area for stickers
    local scroll = Instance.new("ScrollingFrame", panel)
    scroll.Size = UDim2.new(1, -8, 1, -8)
    scroll.Position = UDim2.new(0, 4, 0, 4)
    scroll.BackgroundTransparency = 1
    scroll.ScrollBarThickness = 4
    scroll.ScrollBarImageColor3 = Color3.fromRGB(130, 80, 255)
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.X
    scroll.ScrollingDirection = Enum.ScrollingDirection.X
    scroll.ZIndex = 301

    local grid = Instance.new("UIListLayout", scroll)
    grid.FillDirection = Enum.FillDirection.Horizontal
    grid.VerticalAlignment = Enum.VerticalAlignment.Center
    grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
    grid.Padding = UDim.new(0, 8)
    grid.SortOrder = Enum.SortOrder.LayoutOrder

    local padInner = Instance.new("UIPadding", scroll)
    padInner.PaddingLeft   = UDim.new(0, 6)
    padInner.PaddingRight  = UDim.new(0, 6)
    padInner.PaddingTop    = UDim.new(0, 5)
    padInner.PaddingBottom = UDim.new(0, 5)

    -- Build sticker buttons — premium Instagram-style larger tiles
    for idx, assetId in ipairs(STICKER_IDS) do
        local sBtn = Instance.new("TextButton", scroll)
        sBtn.Size = UDim2.new(0, 100, 0, 100)
        sBtn.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
        sBtn.BackgroundTransparency = 0.0
        sBtn.BorderSizePixel = 0
        sBtn.Text = ""
        sBtn.LayoutOrder = idx
        sBtn.ZIndex = 302
        local sBtnCorner = Instance.new("UICorner", sBtn)
        sBtnCorner.CornerRadius = UDim.new(0, 14)
        local sBtnStroke = Instance.new("UIStroke", sBtn)
        sBtnStroke.Color = Color3.fromRGB(219, 219, 219)
        sBtnStroke.Thickness = 1.5
        sBtnStroke.Transparency = 0.0

        local sImg = Instance.new("ImageLabel", sBtn)
        sImg.Size = UDim2.new(1, -12, 1, -12)
        sImg.Position = UDim2.new(0, 6, 0, 6)
        sImg.BackgroundTransparency = 1
        sImg.Image = "rbxthumb://type=Asset&id=" .. tostring(assetId) .. "&w=150&h=150"
        sImg.ScaleType = Enum.ScaleType.Fit
        sImg.ZIndex = 303

        -- Hover effect
        sBtn.MouseEnter:Connect(function()
            TweenService:Create(sBtn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(230, 230, 230)}):Play()
            sBtnStroke.Transparency = 0.0
        end)
        sBtn.MouseLeave:Connect(function()
            TweenService:Create(sBtn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(245, 245, 245)}):Play()
            sBtnStroke.Transparency = 0.0
        end)

        local capturedId = assetId
        sBtn.MouseButton1Click:Connect(function()
            closeStickerPanel()
            -- Send sticker as a special message: [STICKER:assetId]
            local stickerMsg = "[STICKER:" .. tostring(capturedId) .. "]"
            send(stickerMsg, false, false)
        end)
    end

    StickerPanel = panel

    -- Restore scroll position from last open
    task.spawn(function()
        RunService.Heartbeat:Wait()
        RunService.Heartbeat:Wait()
        if scroll and scroll.Parent then
            scroll.CanvasPosition = Vector2.new(lastStickerScrollX, 0)
        end
    end)

    -- Animate in
    panel.BackgroundTransparency = 1
    TweenService:Create(panel, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {BackgroundTransparency = 0.0}):Play()

    -- Close panel when clicking outside it
    local spConn
    spConn = UserInputService.InputBegan:Connect(function(inp)
        if not panel or not panel.Parent then
            if spConn then spConn:Disconnect() end return
        end
        if inp.UserInputType ~= Enum.UserInputType.MouseButton1
        and inp.UserInputType ~= Enum.UserInputType.Touch then return end
        local p2  = inp.Position
        local ab2 = panel.AbsolutePosition
        local sz2 = panel.AbsoluteSize
        -- Also check the sticker button itself (so clicking it closes instead of re-opening)
        local onBtn = false
        if StickerBtn then
            local abBtn = StickerBtn.AbsolutePosition
            local szBtn = StickerBtn.AbsoluteSize
            onBtn = (p2.X >= abBtn.X and p2.X <= abBtn.X + szBtn.X
                 and p2.Y >= abBtn.Y and p2.Y <= abBtn.Y + szBtn.Y)
        end
        if not onBtn and (p2.X < ab2.X or p2.X > ab2.X + sz2.X or p2.Y < ab2.Y or p2.Y > ab2.Y + sz2.Y) then
            closeStickerPanel()
            if spConn then spConn:Disconnect() end
        end
    end)
end

-- Minimize Button
local MinimizeBtn = Instance.new("TextButton", Header)
MinimizeBtn.Size = UDim2.new(0, 26, 0, 26)
MinimizeBtn.Position = UDim2.new(1, -32, 0.5, -13)
MinimizeBtn.Text = "-"
MinimizeBtn.Font = Enum.Font.GothamBold
MinimizeBtn.TextColor3 = Color3.fromRGB(50, 50, 50)
MinimizeBtn.BackgroundColor3 = Color3.fromRGB(239, 239, 239)
MinimizeBtn.BackgroundTransparency = 0.0
MinimizeBtn.TextSize = 14
MinimizeBtn.ZIndex = 3
Instance.new("UICorner", MinimizeBtn).CornerRadius = UDim.new(1, 0)

-- TAB BUTTONS
local TabButtons = Instance.new("Frame", Main)
TabButtons.Size = UDim2.new(1, -12, 0, 28)
TabButtons.Position = UDim2.new(0, 6, 0, 43)
TabButtons.BackgroundTransparency = 1

local UIListLayoutTab = Instance.new("UIListLayout", TabButtons)
UIListLayoutTab.FillDirection = Enum.FillDirection.Horizontal
UIListLayoutTab.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayoutTab.Padding = UDim.new(0, 4)

local function CreateTabBtn(txt, order, icon)
    local btn = Instance.new("TextButton", TabButtons)
    btn.Size = UDim2.new(0, 55, 1, 0)  -- pixel width; auto-resized below
    btn.Text = icon .. " " .. txt
    btn.Font = Enum.Font.GothamBold
    btn.TextColor3 = Color3.fromRGB(80, 80, 80)
    btn.TextSize = 9
    btn.TextScaled = false
    btn.TextTruncate = Enum.TextTruncate.AtEnd
    btn.LayoutOrder = order
    btn.BackgroundTransparency = 0.0
    btn.BackgroundColor3 = Color3.fromRGB(239, 239, 239)
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke", btn)
    stroke.Color = Color3.fromRGB(200, 200, 200)
    stroke.Thickness = 1
    stroke.Transparency = 0.0
    return btn
end

local ChatTabBtn    = CreateTabBtn("CHAT",    1, "💬")
local FriendsTabBtn = CreateTabBtn("FRIENDS", 2, "👥")
local LeaderboardTabBtn = CreateTabBtn("TOP",   3, "🏆")
local WinnerTabBtn  = CreateTabBtn("WIN",     4, "🥇")

-- ADMIN TAB — visible ONLY for Creator and Owner
local AdminTabBtn
if RealUserId == CREATOR_ID or RealUserId == OWNER_ID then
    AdminTabBtn = CreateTabBtn("ADMIN", 5, "⚙")
end

-- MUSIC TAB — visible ONLY for Creator
local MusicTabBtn
if RealUserId == CREATOR_ID then
    MusicTabBtn = CreateTabBtn("MUSIC", 6, "🎵")
end

-- ============================================================
-- AUTO-RESIZE TABS so all buttons fit equally inside TabButtons
-- frame regardless of how many tabs exist (4 / 5 / 6).
-- TabButtons frame = Main.X(374) - 12 = 362 px wide.
-- UIListLayout padding = 4 px between buttons.
-- tabW = floor( (frameW - (count-1)*gap) / count )
-- ============================================================
do
    local _allTabs = {ChatTabBtn, FriendsTabBtn, LeaderboardTabBtn, WinnerTabBtn}
    if AdminTabBtn then table.insert(_allTabs, AdminTabBtn) end
    if MusicTabBtn then table.insert(_allTabs, MusicTabBtn) end
    local _tabCount = #_allTabs
    local _frameW   = 362   -- 374 - 12 (TabButtons width in pixels)
    local _tabGap   = 4     -- UIListLayoutTab padding
    local _tabW     = math.floor((_frameW - (_tabCount - 1) * _tabGap) / _tabCount)
    for _, _tb in ipairs(_allTabs) do
        _tb.Size = UDim2.new(0, _tabW, 1, 0)
    end
end

-- PAGES FRAME
local Pages = Instance.new("Frame", Main)
Pages.Size = UDim2.new(1, 0, 1, -138)
Pages.Position = UDim2.new(0, 0, 0, 77)
Pages.BackgroundTransparency = 1

-- CHAT PAGE
local ChatPage = Instance.new("Frame", Pages)
ChatPage.Size = UDim2.new(1, 0, 1, 0)
ChatPage.BackgroundTransparency = 1

local ChatLog = Instance.new("ScrollingFrame", ChatPage)
ChatLog.Size = UDim2.new(1, -14, 1, -5)
ChatLog.Position = UDim2.new(0, 7, 0, 5)
ChatLog.BackgroundTransparency = 1
ChatLog.ScrollBarThickness = 3
ChatLog.ScrollBarImageColor3 = Color3.fromRGB(180, 180, 180)
ChatLog.CanvasSize = UDim2.new(0, 0, 0, 0)
ChatLog.AutomaticCanvasSize = Enum.AutomaticSize.Y

local UIList = Instance.new("UIListLayout", ChatLog)
UIList.Padding = UDim.new(0, 4)
UIList.SortOrder = Enum.SortOrder.LayoutOrder

-- ============================================================
-- SCROLL STATE TRACKING + RETURN-TO-BOTTOM BUTTON
-- _userScrolledUp = true  → user scrolled up, auto-scroll paused
-- _userScrolledUp = false → at bottom, auto-scroll active
-- The ↓ button appears when scrolled up; tapping it returns to
-- the bottom and re-enables auto-scroll.
-- ============================================================
local _userScrolledUp = false

local ReturnToBottomBtn = Instance.new("TextButton", ChatPage)
ReturnToBottomBtn.Size = UDim2.new(0, 90, 0, 26)
ReturnToBottomBtn.Position = UDim2.new(0.5, -45, 1, -36)
ReturnToBottomBtn.AnchorPoint = Vector2.new(0, 0)
ReturnToBottomBtn.BackgroundColor3 = Color3.fromRGB(225, 48, 108)
ReturnToBottomBtn.BackgroundTransparency = 0.0
ReturnToBottomBtn.BorderSizePixel = 0
ReturnToBottomBtn.Text = "↓ Latest"
ReturnToBottomBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ReturnToBottomBtn.Font = Enum.Font.GothamBold
ReturnToBottomBtn.TextSize = 12
ReturnToBottomBtn.ZIndex = 10
ReturnToBottomBtn.Visible = false
Instance.new("UICorner", ReturnToBottomBtn).CornerRadius = UDim.new(0, 13)
local _rtbStroke = Instance.new("UIStroke", ReturnToBottomBtn)
_rtbStroke.Color = Color3.fromRGB(225, 48, 108)
_rtbStroke.Thickness = 1.2
_rtbStroke.Transparency = 0.0

ReturnToBottomBtn.MouseButton1Click:Connect(function()
    _userScrolledUp = false
    ReturnToBottomBtn.Visible = false
    ChatLog.CanvasPosition = Vector2.new(0, 99999999)
end)

-- Detect when user scrolls up manually
local _lastCanvasY = 0
ChatLog:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
    local canvas  = ChatLog.CanvasPosition.Y
    local maxY    = ChatLog.AbsoluteCanvasSize.Y - ChatLog.AbsoluteSize.Y
    local atBottom = (maxY <= 0) or (canvas >= maxY - 8)
    if atBottom then
        if _userScrolledUp then
            _userScrolledUp = false
            ReturnToBottomBtn.Visible = false
        end
    else
        if canvas < _lastCanvasY - 2 then
            -- User scrolled up
            if not _userScrolledUp then
                _userScrolledUp = true
                ReturnToBottomBtn.Visible = true
            end
        end
    end
    _lastCanvasY = canvas
end)

-- FRIENDS PAGE
local FriendsPage = Instance.new("Frame", Pages)
FriendsPage.Size = UDim2.new(1, 0, 1, 0)
FriendsPage.BackgroundTransparency = 1
FriendsPage.Name = "FriendsPage"
FriendsPage.Visible = false

local FriendsLog = Instance.new("ScrollingFrame", FriendsPage)
FriendsLog.Size = UDim2.new(1, -14, 1, -5)
FriendsLog.Position = UDim2.new(0, 7, 0, 5)
FriendsLog.BackgroundTransparency = 1
FriendsLog.ScrollBarThickness = 3
FriendsLog.ScrollBarImageColor3 = Color3.fromRGB(180, 180, 180)
FriendsLog.AutomaticCanvasSize = Enum.AutomaticSize.Y

local UIListF = Instance.new("UIListLayout", FriendsLog)
UIListF.Padding = UDim.new(0, 6)

-- LEADERBOARD PAGE
local LeaderboardPage = Instance.new("Frame", Pages)
LeaderboardPage.Size = UDim2.new(1, 0, 1, 0)
LeaderboardPage.BackgroundTransparency = 1
LeaderboardPage.Name = "LeaderboardPage"
LeaderboardPage.Visible = false

local LeaderboardLog = Instance.new("ScrollingFrame", LeaderboardPage)
LeaderboardLog.Size = UDim2.new(1, -14, 1, -5)
LeaderboardLog.Position = UDim2.new(0, 7, 0, 5)
LeaderboardLog.BackgroundTransparency = 1
LeaderboardLog.ScrollBarThickness = 3
LeaderboardLog.ScrollBarImageColor3 = Color3.fromRGB(225, 48, 108)
LeaderboardLog.AutomaticCanvasSize = Enum.AutomaticSize.Y
Instance.new("UIListLayout", LeaderboardLog).Padding = UDim.new(0, 5)

-- WINNER PAGE — Trophy leaderboard (all-time) + this server's session results
local WinnerPage = Instance.new("Frame", Pages)
WinnerPage.Size = UDim2.new(1, 0, 1, 0)
WinnerPage.BackgroundTransparency = 1
WinnerPage.Name = "WinnerPage"
WinnerPage.Visible = false

local WinnerLog = Instance.new("ScrollingFrame", WinnerPage)
WinnerLog.Size = UDim2.new(1, -14, 1, -5)
WinnerLog.Position = UDim2.new(0, 7, 0, 5)
WinnerLog.BackgroundTransparency = 1
WinnerLog.ScrollBarThickness = 3
WinnerLog.ScrollBarImageColor3 = Color3.fromRGB(255, 215, 0)
WinnerLog.AutomaticCanvasSize = Enum.AutomaticSize.Y
Instance.new("UIListLayout", WinnerLog).Padding = UDim.new(0, 5)

-- ADMIN PAGE
local AdminPage = Instance.new("Frame", Pages)
AdminPage.Size = UDim2.new(1, 0, 1, 0)
AdminPage.Visible = false
AdminPage.BackgroundTransparency = 1

local AdminLog = Instance.new("ScrollingFrame", AdminPage)
AdminLog.Size = UDim2.new(1, -14, 1, -5)
AdminLog.Position = UDim2.new(0, 7, 0, 5)
AdminLog.BackgroundTransparency = 1
AdminLog.ScrollBarThickness = 3
AdminLog.ScrollBarImageColor3 = Color3.fromRGB(180, 180, 180)
AdminLog.AutomaticCanvasSize = Enum.AutomaticSize.Y
Instance.new("UIListLayout", AdminLog).Padding = UDim.new(0, 6)

-- ============================================================
-- MUSIC PAGE — Creator-only embedded music player
-- Allows Creator to search SoundCloud and broadcast audio
-- to all script users in the same server via Firebase.
-- Features: Thumbnail | Seek Slider | Shuffle | Loop | Back | Volume
-- ============================================================
local MusicPage = Instance.new("Frame", Pages)
MusicPage.Size = UDim2.new(1, 0, 1, 0)
MusicPage.Visible = false
MusicPage.BackgroundTransparency = 1
MusicPage.Name = "MusicPage"

-- Dark music player background
local MusicBg = Instance.new("Frame", MusicPage)
MusicBg.Size = UDim2.new(1, -10, 1, -5)
MusicBg.Position = UDim2.new(0, 5, 0, 2)
MusicBg.BackgroundColor3 = Color3.fromRGB(14, 14, 14)
MusicBg.BackgroundTransparency = 0.0
MusicBg.BorderSizePixel = 0
Instance.new("UICorner", MusicBg).CornerRadius = UDim.new(0, 10)

-- Now Playing label
local MusicNowPlayingLabel = Instance.new("TextLabel", MusicBg)
MusicNowPlayingLabel.Size = UDim2.new(0.62, 0, 0, 13)
MusicNowPlayingLabel.Position = UDim2.new(0, 6, 0, 3)
MusicNowPlayingLabel.BackgroundTransparency = 1
MusicNowPlayingLabel.Text = "🎵 CREATOR MUSIC PLAYER"
MusicNowPlayingLabel.TextColor3 = Color3.fromRGB(255, 85, 0)
MusicNowPlayingLabel.Font = Enum.Font.GothamBold
MusicNowPlayingLabel.TextSize = 11
MusicNowPlayingLabel.TextXAlignment = Enum.TextXAlignment.Left
MusicNowPlayingLabel.ZIndex = 2

-- Broadcast status label
local MusicBroadcastLabel = Instance.new("TextLabel", MusicBg)
MusicBroadcastLabel.Size = UDim2.new(1, -12, 0, 11)
MusicBroadcastLabel.Position = UDim2.new(0, 6, 0, 17)
MusicBroadcastLabel.BackgroundTransparency = 1
MusicBroadcastLabel.Text = "📡 Broadcasting to this server only"
MusicBroadcastLabel.TextColor3 = Color3.fromRGB(100, 200, 100)
MusicBroadcastLabel.Font = Enum.Font.Gotham
MusicBroadcastLabel.TextSize = 9
MusicBroadcastLabel.TextXAlignment = Enum.TextXAlignment.Left
MusicBroadcastLabel.ZIndex = 2

-- Search Box
local MusicSearchBox = Instance.new("TextBox", MusicBg)
MusicSearchBox.Size = UDim2.new(1, -12, 0, 24)
MusicSearchBox.Position = UDim2.new(0, 6, 0, 31)
MusicSearchBox.BackgroundColor3 = Color3.fromRGB(32, 32, 32)
MusicSearchBox.TextColor3 = Color3.new(1, 1, 1)
MusicSearchBox.PlaceholderText = "Search SoundCloud..."
MusicSearchBox.PlaceholderColor3 = Color3.fromRGB(100, 100, 100)
MusicSearchBox.Font = Enum.Font.Gotham
MusicSearchBox.TextSize = 11
MusicSearchBox.ClearTextOnFocus = false
MusicSearchBox.ZIndex = 2
Instance.new("UICorner", MusicSearchBox).CornerRadius = UDim.new(0, 6)
local _msPad = Instance.new("UIPadding", MusicSearchBox)
_msPad.PaddingLeft = UDim.new(0, 6)

-- Search Button (narrowed to make room for Back button)
local MusicSearchBtn = Instance.new("TextButton", MusicBg)
MusicSearchBtn.Size = UDim2.new(0, 100, 0, 20)
MusicSearchBtn.Position = UDim2.new(0, 6, 0, 58)
MusicSearchBtn.BackgroundColor3 = Color3.fromRGB(255, 85, 0)
MusicSearchBtn.TextColor3 = Color3.new(1, 1, 1)
MusicSearchBtn.Text = "🔍 Search"
MusicSearchBtn.Font = Enum.Font.GothamBold
MusicSearchBtn.TextSize = 11
MusicSearchBtn.ZIndex = 2
Instance.new("UICorner", MusicSearchBtn).CornerRadius = UDim.new(0, 5)

-- Back Button (returns to results list from track view; hidden until results exist)
local MusicBackBtn = Instance.new("TextButton", MusicBg)
MusicBackBtn.Size = UDim2.new(0, 64, 0, 20)
MusicBackBtn.Position = UDim2.new(0, 110, 0, 58)
MusicBackBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
MusicBackBtn.TextColor3 = Color3.new(1, 1, 1)
MusicBackBtn.Text = "← Back"
MusicBackBtn.Font = Enum.Font.GothamBold
MusicBackBtn.TextSize = 11
MusicBackBtn.Visible = false
MusicBackBtn.ZIndex = 2
Instance.new("UICorner", MusicBackBtn).CornerRadius = UDim.new(0, 5)

-- Stop Broadcast Button (right side)
local MusicStopBtn = Instance.new("TextButton", MusicBg)
MusicStopBtn.Size = UDim2.new(0, 78, 0, 20)
MusicStopBtn.AnchorPoint = Vector2.new(1, 0)
MusicStopBtn.Position = UDim2.new(1, -6, 0, 58)
MusicStopBtn.BackgroundColor3 = Color3.fromRGB(180, 30, 30)
MusicStopBtn.TextColor3 = Color3.new(1, 1, 1)
MusicStopBtn.Text = "⏹ Stop"
MusicStopBtn.Font = Enum.Font.GothamBold
MusicStopBtn.TextSize = 11
MusicStopBtn.ZIndex = 2
Instance.new("UICorner", MusicStopBtn).CornerRadius = UDim.new(0, 5)

-- ── Thumbnail (album art — shown when a track is selected) ──────
local MusicThumbnail = Instance.new("ImageLabel", MusicBg)
MusicThumbnail.Name             = "MusicThumbnail"
MusicThumbnail.Size             = UDim2.new(1, -12, 0, 80)
MusicThumbnail.Position         = UDim2.new(0, 6, 0, 82)
MusicThumbnail.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
MusicThumbnail.ScaleType        = Enum.ScaleType.Crop
MusicThumbnail.Image            = ""
MusicThumbnail.Visible          = false
MusicThumbnail.ZIndex           = 2
Instance.new("UICorner", MusicThumbnail).CornerRadius = UDim.new(0, 7)

local MusicThumbPlaceholder = Instance.new("TextLabel", MusicThumbnail)
MusicThumbPlaceholder.Size             = UDim2.new(1, 0, 1, 0)
MusicThumbPlaceholder.BackgroundTransparency = 1
MusicThumbPlaceholder.Text             = "No Artwork"
MusicThumbPlaceholder.TextColor3       = Color3.fromRGB(70, 70, 70)
MusicThumbPlaceholder.Font             = Enum.Font.Gotham
MusicThumbPlaceholder.TextSize         = 10
MusicThumbPlaceholder.ZIndex           = 3

-- Results Panel (scrollable list — same Y as thumbnail, toggled)
local MusicResultsPanel = Instance.new("ScrollingFrame", MusicBg)
MusicResultsPanel.Size = UDim2.new(1, -12, 0, 80)
MusicResultsPanel.Position = UDim2.new(0, 6, 0, 82)
MusicResultsPanel.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
MusicResultsPanel.BorderSizePixel = 0
MusicResultsPanel.ScrollBarThickness = 3
MusicResultsPanel.ScrollBarImageColor3 = Color3.fromRGB(255, 85, 0)
MusicResultsPanel.AutomaticCanvasSize = Enum.AutomaticSize.Y
MusicResultsPanel.CanvasSize = UDim2.new(0, 0, 0, 0)
MusicResultsPanel.Visible = false
MusicResultsPanel.ZIndex = 2
Instance.new("UICorner", MusicResultsPanel).CornerRadius = UDim.new(0, 6)
local MusicResultsLayout = Instance.new("UIListLayout", MusicResultsPanel)
MusicResultsLayout.Padding = UDim.new(0, 2)
MusicResultsLayout.SortOrder = Enum.SortOrder.LayoutOrder
local _mrPad = Instance.new("UIPadding", MusicResultsPanel)
_mrPad.PaddingTop = UDim.new(0, 2)
_mrPad.PaddingLeft = UDim.new(0, 2)
_mrPad.PaddingRight = UDim.new(0, 2)
_mrPad.PaddingBottom = UDim.new(0, 2)

-- Song Title Label (shown below thumbnail)
local MusicSongTitle = Instance.new("TextLabel", MusicBg)
MusicSongTitle.Size = UDim2.new(1, -12, 0, 13)
MusicSongTitle.Position = UDim2.new(0, 6, 0, 166)
MusicSongTitle.BackgroundTransparency = 1
MusicSongTitle.Text = "No song selected"
MusicSongTitle.TextColor3 = Color3.fromRGB(220, 220, 220)
MusicSongTitle.Font = Enum.Font.GothamMedium
MusicSongTitle.TextSize = 10
MusicSongTitle.TextTruncate = Enum.TextTruncate.AtEnd
MusicSongTitle.TextXAlignment = Enum.TextXAlignment.Left
MusicSongTitle.ZIndex = 2

-- Song Duration Label
local MusicSongDuration = Instance.new("TextLabel", MusicBg)
MusicSongDuration.Size = UDim2.new(1, -12, 0, 11)
MusicSongDuration.Position = UDim2.new(0, 6, 0, 180)
MusicSongDuration.BackgroundTransparency = 1
MusicSongDuration.Text = "Duration: 0:00"
MusicSongDuration.TextColor3 = Color3.fromRGB(130, 130, 130)
MusicSongDuration.Font = Enum.Font.Gotham
MusicSongDuration.TextSize = 9
MusicSongDuration.TextXAlignment = Enum.TextXAlignment.Left
MusicSongDuration.ZIndex = 2

-- Playback Controls Row: Prev / Play / Next
local MusicPrevBtn = Instance.new("TextButton", MusicBg)
MusicPrevBtn.Size = UDim2.new(0, 32, 0, 26)
MusicPrevBtn.Position = UDim2.new(0, 6, 0, 194)
MusicPrevBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
MusicPrevBtn.TextColor3 = Color3.new(1, 1, 1)
MusicPrevBtn.Text = "⏮"
MusicPrevBtn.Font = Enum.Font.GothamBold
MusicPrevBtn.TextSize = 13
MusicPrevBtn.ZIndex = 2
Instance.new("UICorner", MusicPrevBtn).CornerRadius = UDim.new(0, 5)

local MusicPlayBtn = Instance.new("TextButton", MusicBg)
MusicPlayBtn.Size = UDim2.new(1, -100, 0, 26)
MusicPlayBtn.Position = UDim2.new(0, 42, 0, 194)
MusicPlayBtn.BackgroundColor3 = Color3.fromRGB(30, 215, 96)
MusicPlayBtn.TextColor3 = Color3.new(1, 1, 1)
MusicPlayBtn.Text = "▶ Play & Broadcast"
MusicPlayBtn.Font = Enum.Font.GothamBold
MusicPlayBtn.TextSize = 11
MusicPlayBtn.ZIndex = 2
Instance.new("UICorner", MusicPlayBtn).CornerRadius = UDim.new(0, 5)

local MusicNextBtn = Instance.new("TextButton", MusicBg)
MusicNextBtn.Size = UDim2.new(0, 32, 0, 26)
MusicNextBtn.AnchorPoint = Vector2.new(1, 0)
MusicNextBtn.Position = UDim2.new(1, -6, 0, 194)
MusicNextBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
MusicNextBtn.TextColor3 = Color3.new(1, 1, 1)
MusicNextBtn.Text = "⏭"
MusicNextBtn.Font = Enum.Font.GothamBold
MusicNextBtn.TextSize = 13
MusicNextBtn.ZIndex = 2
Instance.new("UICorner", MusicNextBtn).CornerRadius = UDim.new(0, 5)

-- Progress Bar (seekable, Spotify-style)
local MusicProgressBG = Instance.new("Frame", MusicBg)
MusicProgressBG.Size = UDim2.new(1, -68, 0, 8)
MusicProgressBG.Position = UDim2.new(0, 6, 0, 226)
MusicProgressBG.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
MusicProgressBG.BorderSizePixel = 0
MusicProgressBG.Active = true
MusicProgressBG.Visible = false
MusicProgressBG.ZIndex = 2
Instance.new("UICorner", MusicProgressBG).CornerRadius = UDim.new(1, 0)

local MusicProgressFill = Instance.new("Frame", MusicProgressBG)
MusicProgressFill.Size = UDim2.new(0, 0, 1, 0)
MusicProgressFill.BackgroundColor3 = Color3.fromRGB(255, 85, 0)
MusicProgressFill.BorderSizePixel = 0
MusicProgressFill.ZIndex = 3
Instance.new("UICorner", MusicProgressFill).CornerRadius = UDim.new(1, 0)

-- Seek Knob (white draggable dot on progress bar)
local MusicSeekKnob = Instance.new("Frame", MusicProgressBG)
MusicSeekKnob.Name             = "MusicSeekKnob"
MusicSeekKnob.Size             = UDim2.new(0, 12, 0, 12)
MusicSeekKnob.AnchorPoint      = Vector2.new(0.5, 0.5)
MusicSeekKnob.Position         = UDim2.new(0, 0, 0.5, 0)
MusicSeekKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
MusicSeekKnob.BorderSizePixel  = 0
MusicSeekKnob.ZIndex           = 4
MusicSeekKnob.Visible          = false
Instance.new("UICorner", MusicSeekKnob).CornerRadius = UDim.new(1, 0)

-- Shuffle Toggle Button
local MusicShuffleBtn = Instance.new("TextButton", MusicBg)
MusicShuffleBtn.Size             = UDim2.new(0, 28, 0, 18)
MusicShuffleBtn.AnchorPoint      = Vector2.new(1, 0)
MusicShuffleBtn.Position         = UDim2.new(1, -36, 0, 222)
MusicShuffleBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
MusicShuffleBtn.TextColor3       = Color3.fromRGB(160, 160, 160)
MusicShuffleBtn.Text             = "🔀"
MusicShuffleBtn.Font             = Enum.Font.GothamBold
MusicShuffleBtn.TextSize         = 11
MusicShuffleBtn.ZIndex           = 2
Instance.new("UICorner", MusicShuffleBtn).CornerRadius = UDim.new(0, 4)

-- Loop Toggle Button
local MusicLoopBtn = Instance.new("TextButton", MusicBg)
MusicLoopBtn.Size             = UDim2.new(0, 28, 0, 18)
MusicLoopBtn.AnchorPoint      = Vector2.new(1, 0)
MusicLoopBtn.Position         = UDim2.new(1, -6, 0, 222)
MusicLoopBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
MusicLoopBtn.TextColor3       = Color3.fromRGB(160, 160, 160)
MusicLoopBtn.Text             = "🔁"
MusicLoopBtn.Font             = Enum.Font.GothamBold
MusicLoopBtn.TextSize         = 11
MusicLoopBtn.ZIndex           = 2
Instance.new("UICorner", MusicLoopBtn).CornerRadius = UDim.new(0, 4)

-- Time labels (current position and total length)
local MusicTimeLeft = Instance.new("TextLabel", MusicBg)
MusicTimeLeft.Size = UDim2.new(0, 40, 0, 10)
MusicTimeLeft.Position = UDim2.new(0, 6, 0, 236)
MusicTimeLeft.BackgroundTransparency = 1
MusicTimeLeft.Text = "0:00"
MusicTimeLeft.TextColor3 = Color3.fromRGB(110, 110, 110)
MusicTimeLeft.Font = Enum.Font.Gotham
MusicTimeLeft.TextSize = 9
MusicTimeLeft.TextXAlignment = Enum.TextXAlignment.Left
MusicTimeLeft.Visible = false
MusicTimeLeft.ZIndex = 2

local MusicTimeRight = Instance.new("TextLabel", MusicBg)
MusicTimeRight.Size = UDim2.new(0, 40, 0, 10)
MusicTimeRight.AnchorPoint = Vector2.new(1, 0)
MusicTimeRight.Position = UDim2.new(1, -6, 0, 236)
MusicTimeRight.BackgroundTransparency = 1
MusicTimeRight.Text = "0:00"
MusicTimeRight.TextColor3 = Color3.fromRGB(110, 110, 110)
MusicTimeRight.Font = Enum.Font.Gotham
MusicTimeRight.TextSize = 9
MusicTimeRight.TextXAlignment = Enum.TextXAlignment.Right
MusicTimeRight.Visible = false
MusicTimeRight.ZIndex = 2

-- Volume Label (click NowPlayingLabel to cycle volume)
local MusicVolLabel = Instance.new("TextLabel", MusicBg)
MusicVolLabel.Size             = UDim2.new(0, 70, 0, 13)
MusicVolLabel.AnchorPoint      = Vector2.new(1, 0)
MusicVolLabel.Position         = UDim2.new(1, -6, 0, 3)
MusicVolLabel.BackgroundTransparency = 1
MusicVolLabel.Text             = "Vol: 100%"
MusicVolLabel.TextColor3       = Color3.fromRGB(120, 120, 120)
MusicVolLabel.Font             = Enum.Font.Gotham
MusicVolLabel.TextSize         = 9
MusicVolLabel.TextXAlignment   = Enum.TextXAlignment.Right
MusicVolLabel.ZIndex           = 2


-- ============================================================
-- REPLY BANNER
-- ============================================================
local ReplyBanner = Instance.new("Frame", Main)
ReplyBanner.Size = UDim2.new(1, -14, 0, 16)
ReplyBanner.Position = UDim2.new(0, 7, 1, -76)
ReplyBanner.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
ReplyBanner.BackgroundTransparency = 0.0
ReplyBanner.BorderSizePixel = 0
ReplyBanner.Visible = false
Instance.new("UICorner", ReplyBanner).CornerRadius = UDim.new(0, 5)
local _replyStroke = Instance.new("UIStroke", ReplyBanner)
_replyStroke.Color = Color3.fromRGB(219, 219, 219)
_replyStroke.Thickness = 1

local ReplyLabel = Instance.new("TextLabel", ReplyBanner)
ReplyLabel.Size = UDim2.new(1, -22, 1, 0)
ReplyLabel.Position = UDim2.new(0, 5, 0, 0)
ReplyLabel.BackgroundTransparency = 1
ReplyLabel.RichText = true
ReplyLabel.Text = "Replying to ..."
ReplyLabel.TextColor3 = Color3.fromRGB(80, 80, 80)
ReplyLabel.Font = Enum.Font.Gotham
ReplyLabel.TextSize = 10
ReplyLabel.TextXAlignment = Enum.TextXAlignment.Left
ReplyLabel.TextTruncate = Enum.TextTruncate.AtEnd

local ReplyCloseBtn = Instance.new("TextButton", ReplyBanner)
ReplyCloseBtn.Size = UDim2.new(0, 16, 1, 0)
ReplyCloseBtn.Position = UDim2.new(1, -18, 0, 0)
ReplyCloseBtn.Text = "X"
ReplyCloseBtn.Font = Enum.Font.GothamBold
ReplyCloseBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
ReplyCloseBtn.BackgroundTransparency = 1
ReplyCloseBtn.TextSize = 10

ReplyCloseBtn.MouseButton1Click:Connect(function()
    ReplyTargetName = nil
    ReplyTargetMsg = nil
    ReplyBanner.Visible = false
    ReplyLabel.Text = "Replying to ..."
end)

-- PVT BANNER REMOVED (user request — banner hidden, PvtInputTag + clearPvt still handle pvt state)

-- INPUT BOX
local InputArea = Instance.new("Frame", Main)
InputArea.Size = UDim2.new(1, -14, 0, 36)
InputArea.Position = UDim2.new(0, 7, 1, -44)
InputArea.BackgroundColor3 = Color3.fromRGB(250, 250, 250)
InputArea.BackgroundTransparency = 0.0
InputArea.BorderSizePixel = 0
Instance.new("UICorner", InputArea).CornerRadius = UDim.new(0, 10)
local InputStroke = Instance.new("UIStroke", InputArea)
InputStroke.Color = Color3.fromRGB(219, 219, 219)
InputStroke.Thickness = 1
InputStroke.Transparency = 0.0

local Input = Instance.new("TextBox", InputArea)
Input.Size = UDim2.new(1, -44, 1, 0)
Input.Position = UDim2.new(0, 8, 0, 0)
Input.PlaceholderText = "* Type a message..."
Input.BackgroundTransparency = 1
Input.TextColor3 = Color3.fromRGB(0, 0, 0)
Input.PlaceholderColor3 = Color3.fromRGB(170, 170, 170)
Input.Font = Enum.Font.Gotham
Input.TextSize = 14
Input.ClearTextOnFocus = true
Input.TextXAlignment = Enum.TextXAlignment.Left

-- Sticker Button — placed to the left of the send button in the InputArea
StickerBtn = Instance.new("TextButton", InputArea)
StickerBtn.Size = UDim2.new(0, 28, 0, 28)
StickerBtn.Position = UDim2.new(1, -74, 0.5, -14)
StickerBtn.Text = "🎭"
StickerBtn.Font = Enum.Font.GothamBold
StickerBtn.TextColor3 = Color3.fromRGB(80, 80, 80)
StickerBtn.BackgroundColor3 = Color3.fromRGB(239, 239, 239)
StickerBtn.BackgroundTransparency = 0.0
StickerBtn.TextSize = 14
StickerBtn.ZIndex = 3
Instance.new("UICorner", StickerBtn).CornerRadius = UDim.new(1, 0)
local StickerBtnStroke = Instance.new("UIStroke", StickerBtn)
StickerBtnStroke.Color = Color3.fromRGB(200, 200, 200)
StickerBtnStroke.Thickness = 1
StickerBtnStroke.Transparency = 0.0
StickerBtn.MouseButton1Click:Connect(openStickerPanel)

-- Shrink input box to make room for sticker button
Input.Size = UDim2.new(1, -82, 1, 0)

-- Send Button
local SendBtn = Instance.new("TextButton", InputArea)
SendBtn.Size = UDim2.new(0, 32, 0, 26)
SendBtn.Position = UDim2.new(1, -38, 0.5, -13)
SendBtn.Text = ">>"
SendBtn.Font = Enum.Font.GothamBold
SendBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
SendBtn.BackgroundColor3 = Color3.fromRGB(225, 48, 108)
SendBtn.BackgroundTransparency = 0.0
SendBtn.TextSize = 14
Instance.new("UICorner", SendBtn).CornerRadius = UDim.new(0, 8)

-- ============================================================
-- CHARACTER COUNTER — shows remaining chars above input area
-- Goes red when approaching limit, hidden when input is empty
-- ============================================================
local CharCounter = Instance.new("TextLabel", Main)
CharCounter.Size = UDim2.new(0, 60, 0, 16)
CharCounter.Position = UDim2.new(1, -68, 1, -62)
CharCounter.BackgroundTransparency = 1
CharCounter.Text = "200"
CharCounter.TextColor3 = Color3.fromRGB(120, 120, 120)
CharCounter.Font = Enum.Font.GothamBold
CharCounter.TextSize = 11
CharCounter.TextXAlignment = Enum.TextXAlignment.Right
CharCounter.ZIndex = 5
CharCounter.Visible = false

Input:GetPropertyChangedSignal("Text"):Connect(function()
    local len = #Input.Text
    local remaining = MAX_CHAR_LIMIT - len
    if len == 0 then
        CharCounter.Visible = false
    else
        CharCounter.Visible = true
        CharCounter.Text = tostring(remaining)
        if remaining <= 20 then
            CharCounter.TextColor3 = Color3.fromRGB(220, 50, 50)
        elseif remaining <= 50 then
            CharCounter.TextColor3 = Color3.fromRGB(200, 140, 30)
        else
            CharCounter.TextColor3 = Color3.fromRGB(120, 120, 120)
        end
    end
    -- Hard clamp: strip characters beyond limit
    if len > MAX_CHAR_LIMIT then
        Input.Text = string.sub(Input.Text, 1, MAX_CHAR_LIMIT)
        Input.CursorPosition = MAX_CHAR_LIMIT + 1
    end
end)

-- ============================================================
-- PVT INPUT TAG — Roblox-chat style "[Name]" label on the
-- LEFT side of the input box shown when private chat is active.
-- Tap this label to DISABLE private chat (only way to clear pvt).
-- ============================================================
local PvtInputTag = Instance.new("TextButton", InputArea)
PvtInputTag.Size = UDim2.new(0, 66, 0, 28)
PvtInputTag.Position = UDim2.new(0, 3, 0.5, -14)
PvtInputTag.BackgroundColor3 = Color3.fromRGB(255, 230, 245)
PvtInputTag.BackgroundTransparency = 0.0
PvtInputTag.Text = "[...]"
PvtInputTag.Font = Enum.Font.GothamBold
PvtInputTag.TextColor3 = Color3.fromRGB(180, 30, 100)
PvtInputTag.TextSize = 11
PvtInputTag.TextTruncate = Enum.TextTruncate.AtEnd
PvtInputTag.Visible = false
PvtInputTag.ZIndex = 4
Instance.new("UICorner", PvtInputTag).CornerRadius = UDim.new(0, 7)
local PvtInputTagStroke = Instance.new("UIStroke", PvtInputTag)
PvtInputTagStroke.Color = Color3.fromRGB(225, 48, 108)
PvtInputTagStroke.Thickness = 1
PvtInputTagStroke.Transparency = 0.2

-- ============================================================
-- TOGGLE BUTTON — bigger, brighter, DRAGGABLE
-- (dragging respects isGuiLocked — when locked, cannot be dragged)
-- ============================================================
local ToggleBtn = Instance.new("TextButton", ScreenGui)
ToggleBtn.Size = UDim2.new(0, 56, 0, 56)
ToggleBtn.Position = UDim2.new(0, 6, 0.72, 0)
ToggleBtn.AnchorPoint = Vector2.new(0, 0.5)
ToggleBtn.Text = "*"
ToggleBtn.TextSize = 22
ToggleBtn.BackgroundColor3 = Color3.fromRGB(225, 48, 108)
ToggleBtn.BackgroundTransparency = 0.0
ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleBtn.Active = true
Instance.new("UICorner", ToggleBtn).CornerRadius = UDim.new(1, 0)
local ToggleStroke = Instance.new("UIStroke", ToggleBtn)
ToggleStroke.Thickness = 2.0
ToggleStroke.Color = Color3.fromRGB(255, 255, 255)
ToggleStroke.Transparency = 0.6

task.spawn(function()
    while ToggleBtn and ToggleBtn.Parent do
        ToggleStroke.Color = Color3.fromRGB(255, 255, 255)
        task.wait(1)
    end
end)

-- ============================================================
-- PVT CLOSE
-- ============================================================
local function clearPvt()
    PrivateTargetId = nil
    PrivateTargetName = nil
    Input.PlaceholderText = "* Type a message..."
    InputArea.BackgroundColor3 = Color3.fromRGB(250, 250, 250)
    -- Hide the left-side pvt name tag and restore input layout
    PvtInputTag.Visible = false
    Input.Position = UDim2.new(0, 8, 0, 0)
    Input.Size = UDim2.new(1, -44, 1, 0)
end

-- Tap the left-side [Name] tag to disable pvt (Roblox-chat style)
PvtInputTag.MouseButton1Click:Connect(clearPvt)

-- ============================================================
-- MESSAGE CONTEXT POPUP — Instagram-style clean premium menu
-- Appears on hold (0.6s):
--   Own messages  → Copy Text / Edit / Unsend
--   Other messages → Copy Text only
-- ============================================================
local MsgPopup = Instance.new("Frame", ScreenGui)
MsgPopup.Name        = "MsgContextPopup"
MsgPopup.Size        = UDim2.new(0, 168, 0, 0)
MsgPopup.AutomaticSize = Enum.AutomaticSize.Y
MsgPopup.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
MsgPopup.BackgroundTransparency = 0.0
MsgPopup.BorderSizePixel = 0
MsgPopup.Visible     = false
MsgPopup.ZIndex      = 200
MsgPopup.ClipsDescendants = true
local _popCorner = Instance.new("UICorner", MsgPopup)
_popCorner.CornerRadius = UDim.new(0, 16)
local _popStroke = Instance.new("UIStroke", MsgPopup)
_popStroke.Color       = Color3.fromRGB(225, 48, 108)
_popStroke.Thickness   = 1.4
_popStroke.Transparency = 0.0
local _popList = Instance.new("UIListLayout", MsgPopup)
_popList.Padding       = UDim.new(0, 0)
_popList.SortOrder     = Enum.SortOrder.LayoutOrder
local _popPad = Instance.new("UIPadding", MsgPopup)
_popPad.PaddingTop    = UDim.new(0, 6)
_popPad.PaddingBottom = UDim.new(0, 6)

local function closeMsgPopup()
    if not MsgPopup.Visible then return end
    TweenService:Create(MsgPopup, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        {BackgroundTransparency = 1}):Play()
    task.delay(0.13, function()
        MsgPopup.Visible = false
        MsgPopup.BackgroundTransparency = 0.0
        for _, c in pairs(MsgPopup:GetChildren()) do
            if c:IsA("TextButton") or c:IsA("Frame") and c.Name == "PopItem" then
                c:Destroy()
            end
        end
    end)
end

local function addPopupItem(icon, label, order, isDestructive, callback)
    local item = Instance.new("TextButton", MsgPopup)
    item.Name             = "PopItem"
    item.Size             = UDim2.new(1, 0, 0, 44)
    item.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    item.BackgroundTransparency = 1
    item.Text             = ""
    item.LayoutOrder      = order
    item.ZIndex           = 201
    item.ClipsDescendants = false

    local iconL = Instance.new("TextLabel", item)
    iconL.Size     = UDim2.new(0, 38, 1, 0)
    iconL.Position = UDim2.new(0, 10, 0, 0)
    iconL.BackgroundTransparency = 1
    iconL.Text     = icon
    iconL.TextSize = 17
    iconL.Font     = Enum.Font.GothamBold
    iconL.TextColor3 = isDestructive and Color3.fromRGB(220, 50, 50) or Color3.fromRGB(30, 30, 30)
    iconL.TextXAlignment = Enum.TextXAlignment.Center
    iconL.ZIndex   = 202

    local textL = Instance.new("TextLabel", item)
    textL.Size     = UDim2.new(1, -58, 1, 0)
    textL.Position = UDim2.new(0, 50, 0, 0)
    textL.BackgroundTransparency = 1
    textL.Text     = label
    textL.Font     = Enum.Font.GothamSemibold
    textL.TextSize = 13
    textL.TextColor3 = isDestructive and Color3.fromRGB(220, 50, 50) or Color3.fromRGB(30, 30, 30)
    textL.TextXAlignment = Enum.TextXAlignment.Left
    textL.ZIndex   = 202

    -- Divider line at bottom of each item (hidden on last via later logic)
    local div = Instance.new("Frame", item)
    div.Name              = "Divider"
    div.Size              = UDim2.new(1, -20, 0, 1)
    div.Position          = UDim2.new(0, 10, 1, -1)
    div.BackgroundColor3  = Color3.fromRGB(219, 219, 219)
    div.BackgroundTransparency = 0.0
    div.BorderSizePixel   = 0
    div.ZIndex            = 202

    -- Hover highlight
    item.MouseEnter:Connect(function()
        TweenService:Create(item, TweenInfo.new(0.1), {BackgroundTransparency = 0.88}):Play()
        item.BackgroundColor3 = isDestructive and Color3.fromRGB(255, 230, 230) or Color3.fromRGB(230, 230, 230)
    end)
    item.MouseLeave:Connect(function()
        TweenService:Create(item, TweenInfo.new(0.1), {BackgroundTransparency = 1}):Play()
    end)

    item.MouseButton1Click:Connect(function()
        closeMsgPopup()
        task.spawn(callback)
    end)

    return item
end

local function showMsgPopup(screenPos, options)
    -- Destroy old items
    for _, c in pairs(MsgPopup:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end

    -- Build items
    for i, opt in ipairs(options) do
        addPopupItem(opt.icon, opt.label, i, opt.destructive or false, opt.callback)
    end

    -- Hide divider on last item
    local items = {}
    for _, c in pairs(MsgPopup:GetChildren()) do
        if c:IsA("TextButton") then table.insert(items, c) end
    end
    table.sort(items, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
    if items[#items] then
        local lastDiv = items[#items]:FindFirstChild("Divider")
        if lastDiv then lastDiv.BackgroundTransparency = 1 end
    end

    -- Compute position — always clamped to stay fully inside the Main GUI frame
    local vpSize  = game.Workspace.CurrentCamera.ViewportSize
    local popW, popH = 168, #options * 44 + 12
    local mainAbs = Main.AbsolutePosition
    local mainSz  = Main.AbsoluteSize
    local guiLeft   = mainAbs.X + 4
    local guiRight  = mainAbs.X + mainSz.X - popW - 4
    local guiTop    = mainAbs.Y + 4
    local guiBottom = mainAbs.Y + mainSz.Y - popH - 4
    local px = math.clamp(screenPos.X - popW / 2, guiLeft, math.max(guiLeft, guiRight))
    local py = screenPos.Y - popH - 10
    if py < guiTop then py = screenPos.Y + 10 end
    py = math.clamp(py, guiTop, math.max(guiTop, guiBottom))

    MsgPopup.Position = UDim2.new(0, px, 0, py)
    MsgPopup.BackgroundTransparency = 1
    MsgPopup.Visible  = true
    TweenService:Create(MsgPopup, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {BackgroundTransparency = 0.0}):Play()
end

-- Dismiss popup when tapping outside it
UserInputService.InputBegan:Connect(function(inp)
    if not MsgPopup.Visible then return end
    if inp.UserInputType ~= Enum.UserInputType.MouseButton1
    and inp.UserInputType ~= Enum.UserInputType.Touch then return end
    local p   = inp.Position
    local abs = MsgPopup.AbsolutePosition
    local sz  = MsgPopup.AbsoluteSize
    if p.X < abs.X or p.X > abs.X + sz.X or p.Y < abs.Y or p.Y > abs.Y + sz.Y then
        closeMsgPopup()
    end
end)


-- ============================================================
-- ADMIN PANEL (CREATOR & OWNER)
-- Now includes expanded admin + normal user command list
-- Ban command shown as CREATOR ONLY
-- Title/Untitle/Unban shown as CREATOR ONLY
-- ============================================================
local function BuildAdminPanel()
    for _, c in pairs(AdminLog:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end

    local isAdmin = (RealUserId == CREATOR_ID or RealUserId == OWNER_ID)

    if not isAdmin then
        local noAccess = Instance.new("TextLabel", AdminLog)
        noAccess.Size = UDim2.new(1, 0, 0, 60)
        noAccess.Text = "[LOCKED] Admin access only"
        noAccess.TextColor3 = Color3.fromRGB(200, 100, 100)
        noAccess.Font = Enum.Font.GothamBold
        noAccess.TextSize = 14
        noAccess.BackgroundTransparency = 1
        return
    end

    -- ADMIN COMMANDS SECTION
    local cmdsTitle = Instance.new("TextLabel", AdminLog)
    cmdsTitle.Size = UDim2.new(1, 0, 0, 28)
    cmdsTitle.Text = "[!] ADMIN COMMANDS (Creator & Owner)"
    cmdsTitle.TextColor3 = Color3.fromRGB(255, 160, 80)
    cmdsTitle.Font = Enum.Font.GothamBold
    cmdsTitle.TextSize = 13
    cmdsTitle.BackgroundTransparency = 1

    local adminCmds = {
        {"/kick [name]",           "Kick a player"},
        {"/ban [name]",            "CREATOR ONLY — Permanent ban"},
        {"/unban [name/id]",       "CREATOR ONLY — Unban a player"},
        {"/title [name] [colour] [text]", "CREATOR ONLY — Custom title (red/white/yellow/black, 1 day)"},
        {"/untitle [name]",        "CREATOR ONLY — Remove custom title instantly"},
        {"/kill [name]",           "Kill a player"},
        {"/re [name]",             "Respawn a player"},
        {"/freeze [name]",         "Freeze a player"},
        {"/unfreeze [name]",       "Unfreeze a player"},
        {"/speed [name] [val]",    "Set player WalkSpeed"},
        {"/jump [name] [val]",     "Set player JumpPower"},
        {"/make [role] [name]",    "Give custom role tag"},
        {"/announce [msg]",        "Broadcast announcement (GLOBAL — all Ares users)"},
        {"/tp2me [name]",          "Teleport player to you"},
        {"/invisible [name]",      "Toggle player invisible"},
        {"/mute [name]",           "Mute player (GUI + bubbles + Firebase)"},
        {"/unmute [name]",         "Unmute player"},
        {"/clear",                 "Clear database (all)"},
    }

    for _, c in ipairs(adminCmds) do
        local row = Instance.new("Frame", AdminLog)
        row.Size = UDim2.new(1, 0, 0, 34)
        row.BackgroundColor3 = Color3.fromRGB(30, 15, 60)
        row.BackgroundTransparency = 0.3
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
        local cmdLbl = Instance.new("TextLabel", row)
        cmdLbl.Size = UDim2.new(0.55, -5, 1, 0)
        cmdLbl.Position = UDim2.new(0, 8, 0, 0)
        cmdLbl.Text = c[1]
        cmdLbl.TextColor3 = Color3.fromRGB(255, 160, 80)
        cmdLbl.Font = Enum.Font.Code
        cmdLbl.TextSize = 10
        cmdLbl.TextXAlignment = Enum.TextXAlignment.Left
        cmdLbl.BackgroundTransparency = 1
        local descLbl = Instance.new("TextLabel", row)
        descLbl.Size = UDim2.new(0.45, -5, 1, 0)
        descLbl.Position = UDim2.new(0.55, 0, 0, 0)
        descLbl.Text = c[2]
        descLbl.TextColor3 = Color3.fromRGB(180, 160, 220)
        descLbl.Font = Enum.Font.Gotham
        descLbl.TextSize = 10
        descLbl.TextXAlignment = Enum.TextXAlignment.Left
        descLbl.BackgroundTransparency = 1
    end

    -- USER COMMANDS SECTION
    local userCmdsTitle = Instance.new("TextLabel", AdminLog)
    userCmdsTitle.Size = UDim2.new(1, 0, 0, 28)
    userCmdsTitle.Text = "[*] USER COMMANDS (Everyone)"
    userCmdsTitle.TextColor3 = Color3.fromRGB(140, 255, 180)
    userCmdsTitle.Font = Enum.Font.GothamBold
    userCmdsTitle.TextSize = 13
    userCmdsTitle.BackgroundTransparency = 1

    local userCmds = {
        {"/fly",              "Toggle fly (local)"},
        {"/noclip",           "Toggle noclip (local)"},
        {"/nosit",            "Disable sit (local)"},
        {"/speed [val]",      "Set own WalkSpeed"},
        {"/jump [val]",       "Set own JumpPower"},
        {"/invisible",        "Toggle own invisible"},
        {"/sit",              "Force sit (local)"},
        {"/me [text]",        "Roleplay action msg"},
        {"/time",             "Show current time"},
        {"/name [text]",      "Change RP display name"},
        {"/mute [name]",      "Locally mute a player (only you)"},
        {"/unmute [name]",    "Locally unmute a player"},
        {"/commands",         "Show all user commands"},
        {"/clear",            "Clear local chat UI"},
    }

    for _, c in ipairs(userCmds) do
        local row = Instance.new("Frame", AdminLog)
        row.Size = UDim2.new(1, 0, 0, 34)
        row.BackgroundColor3 = Color3.fromRGB(10, 30, 20)
        row.BackgroundTransparency = 0.3
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
        local cmdLbl = Instance.new("TextLabel", row)
        cmdLbl.Size = UDim2.new(0.5, -5, 1, 0)
        cmdLbl.Position = UDim2.new(0, 8, 0, 0)
        cmdLbl.Text = c[1]
        cmdLbl.TextColor3 = Color3.fromRGB(140, 255, 180)
        cmdLbl.Font = Enum.Font.Code
        cmdLbl.TextSize = 10
        cmdLbl.TextXAlignment = Enum.TextXAlignment.Left
        cmdLbl.BackgroundTransparency = 1
        local descLbl = Instance.new("TextLabel", row)
        descLbl.Size = UDim2.new(0.5, -5, 1, 0)
        descLbl.Position = UDim2.new(0.5, 0, 0, 0)
        descLbl.Text = c[2]
        descLbl.TextColor3 = Color3.fromRGB(180, 160, 220)
        descLbl.Font = Enum.Font.Gotham
        descLbl.TextSize = 10
        descLbl.TextXAlignment = Enum.TextXAlignment.Left
        descLbl.BackgroundTransparency = 1
    end

    -- PLAYERS IN SERVER SECTION
    local onlineTitle = Instance.new("TextLabel", AdminLog)
    onlineTitle.Size = UDim2.new(1, 0, 0, 28)
    onlineTitle.Text = "[P] PLAYERS IN SERVER"
    onlineTitle.TextColor3 = Color3.fromRGB(200, 170, 255)
    onlineTitle.Font = Enum.Font.GothamBold
    onlineTitle.TextSize = 13
    onlineTitle.BackgroundTransparency = 1

    for _, p in pairs(Players:GetPlayers()) do
        local pRow = Instance.new("Frame", AdminLog)
        pRow.Size = UDim2.new(1, 0, 0, 36)
        pRow.BackgroundColor3 = Color3.fromRGB(25, 12, 50)
        pRow.BackgroundTransparency = 0.3
        Instance.new("UICorner", pRow).CornerRadius = UDim.new(0, 8)

        local pName = Instance.new("TextLabel", pRow)
        pName.Size = UDim2.new(0.55, 0, 1, 0)
        pName.Position = UDim2.new(0, 10, 0, 0)
        pName.Text = p.DisplayName
        pName.TextColor3 = Color3.new(1,1,1)
        pName.Font = Enum.Font.GothamBold
        pName.TextSize = 13
        pName.BackgroundTransparency = 1
        pName.TextXAlignment = Enum.TextXAlignment.Left

        local kickQuick = Instance.new("TextButton", pRow)
        kickQuick.Size = UDim2.new(0, 48, 0, 24)
        kickQuick.Position = UDim2.new(1, -54, 0.5, -12)
        kickQuick.Text = "KICK"
        kickQuick.Font = Enum.Font.GothamBold
        kickQuick.TextSize = 11
        kickQuick.TextColor3 = Color3.new(1,1,1)
        kickQuick.BackgroundColor3 = Color3.fromRGB(180, 30, 30)
        kickQuick.BackgroundTransparency = 0.3
        Instance.new("UICorner", kickQuick).CornerRadius = UDim.new(0, 6)
        kickQuick.MouseButton1Click:Connect(function()
            if p and p.Parent then p:Kick("Kicked by Ares Admin.") end
        end)
    end
end

-- ============================================================
-- PROFILE PAGE — Instagram-style overlay
-- Opens when tapping any user's name in the chat.
-- Shows: pfp, display name, username, bio, followers, follow/unfollow.
-- Titles: [Premium] at 10+ followers, [VIP] at 50+ (if no hardcoded/custom title).
-- ============================================================

-- followState cache so we don't hammer Firebase on every re-open
local followStateCache = {}  -- [targetUid] = true/false
local followerCountCache = {}  -- [targetUid] = number
local followingCountCache = {}  -- [targetUid] = number
local showProfilePage
local addMessage

local function getProfileNameFromCache(uid, profiles)
    uid = tonumber(uid)
    if not uid then return "User" end
    local pdata = profiles and profiles[tostring(uid)]
    if type(pdata) == "table" then
        return tostring(pdata.displayName or pdata.username or ("User " .. tostring(uid)))
    end
    local plr = Players:GetPlayerByUserId(uid)
    if plr then return plr.DisplayName end
    local ok, name = pcall(function()
        return Players:GetNameFromUserIdAsync(uid)
    end)
    if ok and name and name ~= "" then return tostring(name) end
    return "User " .. tostring(uid)
end

local function loadProfileNames(req)
    local profiles = {}
    if not req then return profiles end
    pcall(function()
        local res = req({ Url = PROFILES_URL .. ".json", Method = "GET" })
        if res and res.Success and res.Body ~= "null" then
            local ok, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
            if ok and type(data) == "table" then profiles = data end
        end
    end)
    return profiles
end

local function showFollowListOverlay(targetUid, targetDisplayName, mode)
    local req = syn and syn.request or http and http.request or request
    if not req or not targetUid then return end

    local listOverlay = Instance.new("Frame", ScreenGui)
    listOverlay.Size = Main.Size
    listOverlay.Position = Main.Position
    listOverlay.AnchorPoint = Main.AnchorPoint
    listOverlay.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    listOverlay.BackgroundTransparency = 0.0
    listOverlay.BorderSizePixel = 0
    listOverlay.ZIndex = 650
    listOverlay.ClipsDescendants = true
    Instance.new("UICorner", listOverlay).CornerRadius = UDim.new(0, 16)
    local listStroke = Instance.new("UIStroke", listOverlay)
    listStroke.Color = Color3.fromRGB(225, 48, 108)
    listStroke.Thickness = 1.5

    local listBack = Instance.new("TextButton", listOverlay)
    listBack.Size = UDim2.new(0, 30, 0, 30)
    listBack.Position = UDim2.new(0, 8, 0, 6)
    listBack.Text = "←"
    listBack.Font = Enum.Font.GothamBold
    listBack.TextSize = 18
    listBack.TextColor3 = Color3.fromRGB(50, 50, 50)
    listBack.BackgroundColor3 = Color3.fromRGB(239, 239, 239)
    listBack.ZIndex = 651
    Instance.new("UICorner", listBack).CornerRadius = UDim.new(1, 0)
    listBack.MouseButton1Click:Connect(function()
        if listOverlay and listOverlay.Parent then listOverlay:Destroy() end
    end)

    local title = Instance.new("TextLabel", listOverlay)
    title.Size = UDim2.new(1, -54, 0, 30)
    title.Position = UDim2.new(0, 44, 0, 6)
    title.BackgroundTransparency = 1
    title.Text = tostring(targetDisplayName or "User") .. " " .. (mode == "following" and "Following" or "Followers")
    title.TextColor3 = Color3.fromRGB(0, 0, 0)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 13
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 651

    local divider = Instance.new("Frame", listOverlay)
    divider.Size = UDim2.new(1, 0, 0, 1)
    divider.Position = UDim2.new(0, 0, 0, 40)
    divider.BackgroundColor3 = Color3.fromRGB(219, 219, 219)
    divider.BorderSizePixel = 0
    divider.ZIndex = 651

    local listLog = Instance.new("ScrollingFrame", listOverlay)
    listLog.Size = UDim2.new(1, -14, 1, -48)
    listLog.Position = UDim2.new(0, 7, 0, 44)
    listLog.BackgroundTransparency = 1
    listLog.ScrollBarThickness = 3
    listLog.ScrollBarImageColor3 = Color3.fromRGB(225, 48, 108)
    listLog.AutomaticCanvasSize = Enum.AutomaticSize.Y
    listLog.ZIndex = 651
    local listLayout = Instance.new("UIListLayout", listLog)
    listLayout.Padding = UDim.new(0, 5)
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local loading = Instance.new("TextLabel", listLog)
    loading.Size = UDim2.new(1, 0, 0, 36)
    loading.BackgroundTransparency = 1
    loading.Text = "Loading..."
    loading.TextColor3 = Color3.fromRGB(160, 160, 160)
    loading.Font = Enum.Font.Gotham
    loading.TextSize = 12
    loading.ZIndex = 652

    task.spawn(function()
        local allFollowers = {}
        local profiles = loadProfileNames(req)
        pcall(function()
            local res = req({ Url = FOLLOWERS_URL .. ".json", Method = "GET" })
            if res and res.Success and res.Body ~= "null" then
                local ok, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
                if ok and type(data) == "table" then allFollowers = data end
            end
        end)

        local uidStr = tostring(targetUid)
        local rows = {}
        if mode == "following" then
            for followedUid, followers in pairs(allFollowers) do
                if type(followers) == "table" and followers[uidStr] then
                    local fuid = tonumber(followedUid)
                    if fuid then table.insert(rows, fuid) end
                end
            end
        else
            local followers = allFollowers[uidStr]
            if type(followers) == "table" then
                for followerUid, _ in pairs(followers) do
                    local fuid = tonumber(followerUid)
                    if fuid then table.insert(rows, fuid) end
                end
            end
        end
        table.sort(rows, function(a, b)
            return getProfileNameFromCache(a, profiles) < getProfileNameFromCache(b, profiles)
        end)

        if loading and loading.Parent then loading:Destroy() end
        if #rows == 0 then
            local empty = Instance.new("TextLabel", listLog)
            empty.Size = UDim2.new(1, 0, 0, 42)
            empty.BackgroundTransparency = 1
            empty.Text = mode == "following" and "Not following anyone yet." or "No followers yet."
            empty.TextColor3 = Color3.fromRGB(160, 160, 160)
            empty.Font = Enum.Font.Gotham
            empty.TextSize = 12
            empty.ZIndex = 652
            return
        end

        for _, uid in ipairs(rows) do
            local rowName = getProfileNameFromCache(uid, profiles)
            local row = Instance.new("TextButton", listLog)
            row.Size = UDim2.new(1, -4, 0, 48)
            row.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
            row.BackgroundTransparency = 0.0
            row.BorderSizePixel = 0
            row.Text = ""
            row.AutoButtonColor = true
            row.ZIndex = 652
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)
            local rowStroke = Instance.new("UIStroke", row)
            rowStroke.Color = Color3.fromRGB(219, 219, 219)
            rowStroke.Thickness = 1

            local img = Instance.new("ImageLabel", row)
            img.Size = UDim2.new(0, 34, 0, 34)
            img.Position = UDim2.new(0, 8, 0.5, -17)
            img.BackgroundColor3 = Color3.fromRGB(220, 220, 220)
            img.BorderSizePixel = 0
            img.ZIndex = 653
            Instance.new("UICorner", img).CornerRadius = UDim.new(1, 0)
            task.spawn(function()
                pcall(function()
                    local content, ready = Players:GetUserThumbnailAsync(uid, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
                    if ready and img and img.Parent then img.Image = content end
                end)
            end)

            local lbl = Instance.new("TextLabel", row)
            lbl.Size = UDim2.new(1, -56, 1, 0)
            lbl.Position = UDim2.new(0, 50, 0, 0)
            lbl.BackgroundTransparency = 1
            lbl.Text = rowName
            lbl.TextColor3 = Color3.fromRGB(0, 0, 0)
            lbl.Font = Enum.Font.GothamBold
            lbl.TextSize = 13
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.TextTruncate = Enum.TextTruncate.AtEnd
            lbl.ZIndex = 653

            row.MouseButton1Click:Connect(function()
                if showProfilePage then showProfilePage(uid, rowName, rowName) end
            end)
        end
    end)
end

showProfilePage = function(targetUid, targetDisplayName, targetUsername)
    if not targetUid or targetUid == 0 then return end

    -- Overlay frame that matches Main in size and position
    local overlay = Instance.new("Frame", ScreenGui)
    overlay.Size = Main.Size
    overlay.Position = Main.Position
    overlay.AnchorPoint = Main.AnchorPoint
    overlay.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    overlay.BackgroundTransparency = 0.0
    overlay.BorderSizePixel = 0
    overlay.ZIndex = 500
    overlay.ClipsDescendants = true
    local ovCorner = Instance.new("UICorner", overlay)
    ovCorner.CornerRadius = UDim.new(0, 16)
    local ovStroke = Instance.new("UIStroke", overlay)
    ovStroke.Color = Color3.fromRGB(225, 48, 108)
    ovStroke.Thickness = 1.5
    ovStroke.Transparency = 0.0

    -- Slide-in animation (from right, like Instagram)
    overlay.Position = UDim2.new(Main.Position.X.Scale, Main.Position.X.Offset + 380,
                                  Main.Position.Y.Scale, Main.Position.Y.Offset)
    TweenService:Create(overlay, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Position = Main.Position}):Play()

    -- Back button (←)
    local backBtn = Instance.new("TextButton", overlay)
    backBtn.Size = UDim2.new(0, 30, 0, 30)
    backBtn.Position = UDim2.new(0, 8, 0, 6)
    backBtn.Text = "←"
    backBtn.Font = Enum.Font.GothamBold
    backBtn.TextSize = 18
    backBtn.TextColor3 = Color3.fromRGB(50, 50, 50)
    backBtn.BackgroundColor3 = Color3.fromRGB(239, 239, 239)
    backBtn.BackgroundTransparency = 0.0
    backBtn.ZIndex = 501
    Instance.new("UICorner", backBtn).CornerRadius = UDim.new(1, 0)
    backBtn.MouseButton1Click:Connect(function()
        TweenService:Create(overlay, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            {Position = UDim2.new(Main.Position.X.Scale, Main.Position.X.Offset + 380,
                                   Main.Position.Y.Scale, Main.Position.Y.Offset)}):Play()
        task.delay(0.2, function() if overlay and overlay.Parent then overlay:Destroy() end end)
    end)

    -- Profile header label
    local profileTitle = Instance.new("TextLabel", overlay)
    profileTitle.Size = UDim2.new(1, -50, 0, 30)
    profileTitle.Position = UDim2.new(0, 44, 0, 6)
    profileTitle.BackgroundTransparency = 1
    profileTitle.Text = "Profile"
    profileTitle.TextColor3 = Color3.fromRGB(0, 0, 0)
    profileTitle.Font = Enum.Font.GothamBold
    profileTitle.TextSize = 14
    profileTitle.TextXAlignment = Enum.TextXAlignment.Left
    profileTitle.ZIndex = 501

    -- Divider under header
    local profDivider = Instance.new("Frame", overlay)
    profDivider.Size = UDim2.new(1, 0, 0, 1)
    profDivider.Position = UDim2.new(0, 0, 0, 40)
    profDivider.BackgroundColor3 = Color3.fromRGB(219, 219, 219)
    profDivider.BorderSizePixel = 0
    profDivider.ZIndex = 501

    -- PFP circle
    local pfpCircle = Instance.new("Frame", overlay)
    pfpCircle.Size = UDim2.new(0, 72, 0, 72)
    pfpCircle.Position = UDim2.new(0, 14, 0, 52)
    pfpCircle.BackgroundColor3 = Color3.fromRGB(220, 220, 220)
    pfpCircle.BorderSizePixel = 0
    pfpCircle.ZIndex = 501
    Instance.new("UICorner", pfpCircle).CornerRadius = UDim.new(1, 0)
    local pfpStroke = Instance.new("UIStroke", pfpCircle)
    pfpStroke.Color = Color3.fromRGB(225, 48, 108)
    pfpStroke.Thickness = 2
    pfpStroke.Transparency = 0.0

    local pfpImg = Instance.new("ImageLabel", pfpCircle)
    pfpImg.Size = UDim2.new(1, 0, 1, 0)
    pfpImg.BackgroundTransparency = 1
    pfpImg.ZIndex = 502
    Instance.new("UICorner", pfpImg).CornerRadius = UDim.new(1, 0)

    -- Followers count box
    local followerBox = Instance.new("TextButton", overlay)
    followerBox.Size = UDim2.new(0, 70, 0, 44)
    followerBox.Position = UDim2.new(1, -160, 0, 54)
    followerBox.BackgroundTransparency = 1
    followerBox.Text = ""
    followerBox.AutoButtonColor = false
    followerBox.ZIndex = 501

    local followerCount = Instance.new("TextLabel", followerBox)
    followerCount.Size = UDim2.new(1, 0, 0, 24)
    followerCount.Position = UDim2.new(0, 0, 0, 0)
    followerCount.BackgroundTransparency = 1
    followerCount.Text = "—"
    followerCount.TextColor3 = Color3.fromRGB(0, 0, 0)
    followerCount.Font = Enum.Font.GothamBold
    followerCount.TextSize = 18
    followerCount.TextXAlignment = Enum.TextXAlignment.Center
    followerCount.ZIndex = 502

    local followerLabel = Instance.new("TextLabel", followerBox)
    followerLabel.Size = UDim2.new(1, 0, 0, 16)
    followerLabel.Position = UDim2.new(0, 0, 0, 26)
    followerLabel.BackgroundTransparency = 1
    followerLabel.Text = "Followers"
    followerLabel.TextColor3 = Color3.fromRGB(120, 120, 120)
    followerLabel.Font = Enum.Font.Gotham
    followerLabel.TextSize = 11
    followerLabel.TextXAlignment = Enum.TextXAlignment.Center
    followerLabel.ZIndex = 502

    local followingBox = Instance.new("TextButton", overlay)
    followingBox.Size = UDim2.new(0, 70, 0, 44)
    followingBox.Position = UDim2.new(1, -82, 0, 54)
    followingBox.BackgroundTransparency = 1
    followingBox.Text = ""
    followingBox.AutoButtonColor = false
    followingBox.ZIndex = 501

    local followingCount = Instance.new("TextLabel", followingBox)
    followingCount.Size = UDim2.new(1, 0, 0, 24)
    followingCount.Position = UDim2.new(0, 0, 0, 0)
    followingCount.BackgroundTransparency = 1
    followingCount.Text = "—"
    followingCount.TextColor3 = Color3.fromRGB(0, 0, 0)
    followingCount.Font = Enum.Font.GothamBold
    followingCount.TextSize = 18
    followingCount.TextXAlignment = Enum.TextXAlignment.Center
    followingCount.ZIndex = 502

    local followingLabel = Instance.new("TextLabel", followingBox)
    followingLabel.Size = UDim2.new(1, 0, 0, 16)
    followingLabel.Position = UDim2.new(0, 0, 0, 26)
    followingLabel.BackgroundTransparency = 1
    followingLabel.Text = "Following"
    followingLabel.TextColor3 = Color3.fromRGB(120, 120, 120)
    followingLabel.Font = Enum.Font.Gotham
    followingLabel.TextSize = 11
    followingLabel.TextXAlignment = Enum.TextXAlignment.Center
    followingLabel.ZIndex = 502

    followerBox.MouseButton1Click:Connect(function()
        showFollowListOverlay(targetUid, targetDisplayName, "followers")
    end)
    followingBox.MouseButton1Click:Connect(function()
        showFollowListOverlay(targetUid, targetDisplayName, "following")
    end)

    -- Display name row — RichText prefix: "[VIP] DisplayName" or "[Premium] DisplayName"
    -- The prefix is set asynchronously once the follower count loads.
    local displayNameLabel = Instance.new("TextLabel", overlay)
    displayNameLabel.Size = UDim2.new(1, -24, 0, 22)
    displayNameLabel.Position = UDim2.new(0, 14, 0, 132)
    displayNameLabel.BackgroundTransparency = 1
    displayNameLabel.RichText = true
    displayNameLabel.Text = "<b>" .. targetDisplayName .. "</b>"
    displayNameLabel.TextColor3 = Color3.fromRGB(0, 0, 0)
    displayNameLabel.Font = Enum.Font.GothamBold
    displayNameLabel.TextSize = 16
    displayNameLabel.TextXAlignment = Enum.TextXAlignment.Left
    displayNameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    displayNameLabel.ZIndex = 502

    -- Helper: updates the display name label with the correct title prefix.
    -- Call this whenever the follower count becomes known.
    local function applyProfileTitle(fTitleType, hasTag)
        if not displayNameLabel or not displayNameLabel.Parent then return end
        if not fTitleType or hasTag then
            -- No title — plain bold name
            displayNameLabel.Text = "<b>" .. targetDisplayName .. "</b>"
        elseif fTitleType == "VIP" then
            -- Gold/yellow prefix inline with name
            displayNameLabel.Text = "<font color='rgb(220,160,0)'><b>[VIP]</b></font> <b>" .. targetDisplayName .. "</b>"
        elseif fTitleType == "Legend" then
            -- Red prefix inline with name
            displayNameLabel.Text = "<font color='rgb(220,30,30)'><b>[Legend]</b></font> <b>" .. targetDisplayName .. "</b>"
        elseif fTitleType == "Premium" then
            -- Simple light blue prefix inline with name
            displayNameLabel.Text = "<font color='rgb(100,185,255)'><b>[Premium]</b></font> <b>" .. targetDisplayName .. "</b>"
        end
    end

    -- Username label — sits directly below the display name (no overlap)
    local usernameLabel = Instance.new("TextLabel", overlay)
    usernameLabel.Size = UDim2.new(1, -24, 0, 18)
    usernameLabel.Position = UDim2.new(0, 14, 0, 156)
    usernameLabel.BackgroundTransparency = 1
    usernameLabel.Text = "@" .. (targetUsername or targetDisplayName)
    usernameLabel.TextColor3 = Color3.fromRGB(120, 120, 120)
    usernameLabel.Font = Enum.Font.Gotham
    usernameLabel.TextSize = 12
    usernameLabel.TextXAlignment = Enum.TextXAlignment.Left
    usernameLabel.ZIndex = 501

    -- Bio label
    local bioLabel = Instance.new("TextLabel", overlay)
    bioLabel.Size = UDim2.new(1, -24, 0, 32)
    bioLabel.Position = UDim2.new(0, 14, 0, 180)
    bioLabel.BackgroundTransparency = 1
    bioLabel.Text = "No bio yet."
    bioLabel.TextColor3 = Color3.fromRGB(60, 60, 60)
    bioLabel.Font = Enum.Font.Gotham
    bioLabel.TextSize = 12
    bioLabel.TextXAlignment = Enum.TextXAlignment.Left
    bioLabel.TextWrapped = true
    bioLabel.ZIndex = 501

    -- Trophy count label (loaded async from Firebase)
    local trophyLabel = Instance.new("TextLabel", overlay)
    trophyLabel.Size = UDim2.new(1, -24, 0, 18)
    trophyLabel.Position = UDim2.new(0, 14, 0, 214)
    trophyLabel.BackgroundTransparency = 1
    trophyLabel.Text = "🏆 Trophies: ..."
    trophyLabel.TextColor3 = Color3.fromRGB(200, 160, 0)
    trophyLabel.Font = Enum.Font.GothamBold
    trophyLabel.TextSize = 12
    trophyLabel.TextXAlignment = Enum.TextXAlignment.Left
    trophyLabel.ZIndex = 502

    -- Divider before follow button
    local btnDivider = Instance.new("Frame", overlay)
    btnDivider.Size = UDim2.new(1, -28, 0, 1)
    btnDivider.Position = UDim2.new(0, 14, 0, 238)
    btnDivider.BackgroundColor3 = Color3.fromRGB(219, 219, 219)
    btnDivider.BorderSizePixel = 0
    btnDivider.ZIndex = 501

    -- Follow / Unfollow button
    local followBtn = Instance.new("TextButton", overlay)
    followBtn.Size = UDim2.new(1, -28, 0, 36)
    followBtn.Position = UDim2.new(0, 14, 0, 246)
    followBtn.BackgroundColor3 = Color3.fromRGB(225, 48, 108)
    followBtn.BackgroundTransparency = 0.0
    followBtn.BorderSizePixel = 0
    followBtn.Text = "Follow"
    followBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    followBtn.Font = Enum.Font.GothamBold
    followBtn.TextSize = 14
    followBtn.ZIndex = 501
    Instance.new("UICorner", followBtn).CornerRadius = UDim.new(0, 8)

    -- Follow button state toggle
    local isFollowing = false
    local function updateFollowBtn(following)
        isFollowing = following
        if following then
            followBtn.Text = "Following ✓"
            followBtn.BackgroundColor3 = Color3.fromRGB(239, 239, 239)
            followBtn.TextColor3 = Color3.fromRGB(50, 50, 50)
        else
            followBtn.Text = "Follow"
            followBtn.BackgroundColor3 = Color3.fromRGB(225, 48, 108)
            followBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        end
        followStateCache[targetUid] = following
    end

    followBtn.MouseButton1Click:Connect(function()
        -- ============================================================
        -- ALT PROTECTION: Require minimum account age of 7 days.
        -- Fake/alt accounts are typically created seconds before use.
        -- Blocking them ensures only real accounts can follow.
        -- ============================================================
        if LocalPlayer.AccountAge < 7 then
            addMessage("SYSTEM", "DON'T USE FAKE ACCOUNTS TO FOLLOW😡", true, 0, 0, false, true)
            return
        end
        local req = syn and syn.request or http and http.request or request
        if not req then return end
        local myUidStr = tostring(RealUserId)
        local targetUidStr = tostring(targetUid)
        if isFollowing then
            -- Unfollow
            pcall(function()
                req({ Url = FOLLOWERS_URL .. "/" .. targetUidStr .. "/" .. myUidStr .. ".json", Method = "DELETE" })
            end)
            updateFollowBtn(false)
            -- Decrement local cache
            followerCountCache[targetUid] = math.max(0, (followerCountCache[targetUid] or 1) - 1)
            followerCount.Text = tostring(followerCountCache[targetUid])
        else
            -- Follow
            pcall(function()
                req({ Url = FOLLOWERS_URL .. "/" .. targetUidStr .. "/" .. myUidStr .. ".json",
                      Method = "PUT", Body = HttpService:JSONEncode(true) })
                -- Write display name to profile so leaderboard can show it
                req({ Url = PROFILES_URL .. "/" .. targetUidStr .. "/displayName.json",
                      Method = "PUT", Body = HttpService:JSONEncode(targetDisplayName) })
                req({ Url = PROFILES_URL .. "/" .. targetUidStr .. "/username.json",
                      Method = "PUT", Body = HttpService:JSONEncode(targetUsername or targetDisplayName) })
            end)
            updateFollowBtn(true)
            followerCountCache[targetUid] = (followerCountCache[targetUid] or 0) + 1
            followerCount.Text = tostring(followerCountCache[targetUid])
        end
        -- Update follower title prefix after follow state changes
        local fc = followerCountCache[targetUid] or 0
        badgeCache[targetUid] = fc
        local fTitleType = getFollowerTitleTypeFromCount(fc)
        local hasTag = (targetUid == CREATOR_ID or targetUid == OWNER_ID
            or CUTE_IDS[targetUid] or HELLGOD_IDS[targetUid]
            or VIP_IDS[targetUid] or GOD_IDS[targetUid]
            or DADDY_IDS[targetUid] or REAPER_IDS[targetUid]
            or PAPA_MVP_IDS[targetUid] or CustomTitles[targetUid])
        applyProfileTitle(fTitleType, hasTag)
    end)

    -- Async: load pfp, follower count, bio, follow state
    task.spawn(function()
        -- Load pfp
        pcall(function()
            local content, ready = Players:GetUserThumbnailAsync(targetUid, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
            if ready and pfpImg and pfpImg.Parent then pfpImg.Image = content end
        end)

        local req = syn and syn.request or http and http.request or request
        if not req then return end
        local targetUidStr = tostring(targetUid)
        local myUidStr = tostring(RealUserId)

        -- Load follower count
        pcall(function()
            local res = req({ Url = FOLLOWERS_URL .. "/" .. targetUidStr .. ".json", Method = "GET" })
            if res and res.Success and res.Body ~= "null" then
                local ok, fdata = pcall(HttpService.JSONDecode, HttpService, res.Body)
                if ok and type(fdata) == "table" then
                    local count = 0
                    for _ in pairs(fdata) do count = count + 1 end
                    followerCountCache[targetUid] = count
                    if followerCount and followerCount.Parent then
                        followerCount.Text = tostring(count)
                    end
                    -- Follower title prefix logic
                    badgeCache[targetUid] = count
                    local fTitleType2 = getFollowerTitleTypeFromCount(count)
                    local hasTag2 = (targetUid == CREATOR_ID or targetUid == OWNER_ID
                        or CUTE_IDS[targetUid] or HELLGOD_IDS[targetUid]
                        or VIP_IDS[targetUid] or GOD_IDS[targetUid]
                        or DADDY_IDS[targetUid] or REAPER_IDS[targetUid]
                        or PAPA_MVP_IDS[targetUid] or CustomTitles[targetUid])
                    applyProfileTitle(fTitleType2, hasTag2)
                else
                    followerCountCache[targetUid] = 0
                    if followerCount and followerCount.Parent then
                        followerCount.Text = "0"
                    end
                end
            else
                followerCountCache[targetUid] = 0
                if followerCount and followerCount.Parent then
                    followerCount.Text = "0"
                end
            end
        end)

        -- Load following count
        pcall(function()
            local res = req({ Url = FOLLOWERS_URL .. ".json", Method = "GET" })
            local count = 0
            if res and res.Success and res.Body ~= "null" then
                local ok, allData = pcall(HttpService.JSONDecode, HttpService, res.Body)
                if ok and type(allData) == "table" then
                    for _, followers in pairs(allData) do
                        if type(followers) == "table" and followers[targetUidStr] then
                            count = count + 1
                        end
                    end
                end
            end
            followingCountCache[targetUid] = count
            if followingCount and followingCount.Parent then
                followingCount.Text = tostring(count)
            end
        end)

        -- Check if I follow this person
        pcall(function()
            local res = req({ Url = FOLLOWERS_URL .. "/" .. targetUidStr .. "/" .. myUidStr .. ".json", Method = "GET" })
            local following = (res and res.Success and res.Body ~= "null" and res.Body ~= "false")
            if followBtn and followBtn.Parent then
                updateFollowBtn(following)
            end
        end)

        -- Load bio from profiles
        pcall(function()
            local res = req({ Url = PROFILES_URL .. "/" .. targetUidStr .. "/bio.json", Method = "GET" })
            if res and res.Success and res.Body ~= "null" then
                local ok, bio = pcall(HttpService.JSONDecode, HttpService, res.Body)
                if ok and type(bio) == "string" and bio ~= "" then
                    if bioLabel and bioLabel.Parent then
                        bioLabel.Text = bio
                    end
                end
            end
        end)

        -- Load trophy count from Firebase
        pcall(function()
            local res = req({ Url = TROPHIES_URL .. "/" .. targetUidStr .. ".json", Method = "GET" })
            local tCount = 0
            if res and res.Success and res.Body ~= "null" then
                local ok, tdata = pcall(HttpService.JSONDecode, HttpService, res.Body)
                if ok and type(tdata) == "table" then
                    tCount = tonumber(tdata.count) or 0
                end
            end
            trophyCache[targetUid] = tCount
            if trophyLabel and trophyLabel.Parent then
                trophyLabel.Text = "🏆 Trophies: " .. tostring(tCount)
            end
        end)
    end)
end

-- ============================================================
-- LEADERBOARD — show all users sorted by follower count.
-- Black tick at 10+ followers (asset 133491151390631)
-- Blue tick at 50+ followers (asset 90389981305470)
-- ============================================================
function RefreshLeaderboard()
    for _, child in pairs(LeaderboardLog:GetChildren()) do
        if not child:IsA("UIListLayout") then child:Destroy() end
    end

    -- Loading label
    local loadingLbl = Instance.new("TextLabel", LeaderboardLog)
    loadingLbl.Size = UDim2.new(1, 0, 0, 30)
    loadingLbl.BackgroundTransparency = 1
    loadingLbl.Text = "Loading leaderboard..."
    loadingLbl.TextColor3 = Color3.fromRGB(180, 180, 180)
    loadingLbl.Font = Enum.Font.Gotham
    loadingLbl.TextSize = 12

    task.spawn(function()
        local req = syn and syn.request or http and http.request or request
        if not req then
            if loadingLbl and loadingLbl.Parent then loadingLbl:Destroy() end
            return
        end

        -- Fetch all followers data
        local allFollowers = {}
        pcall(function()
            local res = req({ Url = FOLLOWERS_URL .. ".json", Method = "GET" })
            if res and res.Success and res.Body ~= "null" then
                local ok, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
                if ok and type(data) == "table" then
                    for uidStr, followers in pairs(data) do
                        local uid = tonumber(uidStr)
                        if uid and type(followers) == "table" then
                            local count = 0
                            for _ in pairs(followers) do count = count + 1 end
                            if count > 0 then
                                allFollowers[uid] = count
                            end
                        end
                    end
                end
            end
        end)

        -- Fetch display names from profiles
        local profileNames = {}
        pcall(function()
            local res = req({ Url = PROFILES_URL .. ".json", Method = "GET" })
            if res and res.Success and res.Body ~= "null" then
                local ok, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
                if ok and type(data) == "table" then
                    for uidStr, pdata in pairs(data) do
                        local uid = tonumber(uidStr)
                        if uid and type(pdata) == "table" then
                            profileNames[uid] = pdata.displayName or pdata.username or ("User " .. uidStr)
                        end
                    end
                end
            end
        end)

        -- Remove loading label
        if loadingLbl and loadingLbl.Parent then loadingLbl:Destroy() end
        for _, child in pairs(LeaderboardLog:GetChildren()) do
            if not child:IsA("UIListLayout") then child:Destroy() end
        end

        -- Sort by follower count descending
        local sorted = {}
        for uid, count in pairs(allFollowers) do
            table.insert(sorted, { uid = uid, count = count })
        end
        table.sort(sorted, function(a, b) return a.count > b.count end)

        if #sorted == 0 then
            local emptyLbl = Instance.new("TextLabel", LeaderboardLog)
            emptyLbl.Size = UDim2.new(1, 0, 0, 40)
            emptyLbl.BackgroundTransparency = 1
            emptyLbl.Text = "No followers data yet."
            emptyLbl.TextColor3 = Color3.fromRGB(180, 180, 180)
            emptyLbl.Font = Enum.Font.Gotham
            emptyLbl.TextSize = 12
            return
        end

        -- Header
        local headerLbl = Instance.new("TextLabel", LeaderboardLog)
        headerLbl.Size = UDim2.new(1, 0, 0, 24)
        headerLbl.BackgroundTransparency = 1
        headerLbl.Text = "🏆  Top Followers Leaderboard"
        headerLbl.TextColor3 = Color3.fromRGB(225, 48, 108)
        headerLbl.Font = Enum.Font.GothamBold
        headerLbl.TextSize = 13
        headerLbl.TextXAlignment = Enum.TextXAlignment.Left

        for rank, entry in ipairs(sorted) do
            local uid = entry.uid
            local count = entry.count
            local displayName = profileNames[uid] or ("User " .. tostring(uid))

            local row = Instance.new("Frame", LeaderboardLog)
            row.Size = UDim2.new(1, -4, 0, 46)
            row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            row.BackgroundTransparency = 0.0
            row.BorderSizePixel = 0
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)
            local rowStroke = Instance.new("UIStroke", row)
            rowStroke.Color = Color3.fromRGB(219, 219, 219)
            rowStroke.Thickness = 1

            -- Rank number
            local rankLbl = Instance.new("TextLabel", row)
            rankLbl.Size = UDim2.new(0, 28, 1, 0)
            rankLbl.Position = UDim2.new(0, 4, 0, 0)
            rankLbl.BackgroundTransparency = 1
            rankLbl.Text = tostring(rank)
            rankLbl.TextColor3 = rank == 1 and Color3.fromRGB(255, 180, 0)
                              or rank == 2 and Color3.fromRGB(180, 180, 180)
                              or rank == 3 and Color3.fromRGB(180, 100, 50)
                              or Color3.fromRGB(120, 120, 120)
            rankLbl.Font = Enum.Font.GothamBold
            rankLbl.TextSize = 14
            rankLbl.TextXAlignment = Enum.TextXAlignment.Center

            -- PFP
            local lbPfp = Instance.new("ImageButton", row)
            lbPfp.Size = UDim2.new(0, 32, 0, 32)
            lbPfp.Position = UDim2.new(0, 34, 0.5, -16)
            lbPfp.BackgroundColor3 = Color3.fromRGB(220, 220, 220)
            lbPfp.BorderSizePixel = 0
            lbPfp.AutoButtonColor = false
            Instance.new("UICorner", lbPfp).CornerRadius = UDim.new(1, 0)
            lbPfp.MouseButton1Click:Connect(function()
                showProfilePage(uid, displayName, displayName)
            end)
            task.spawn(function()
                pcall(function()
                    local content, ready = Players:GetUserThumbnailAsync(uid, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
                    if ready and lbPfp and lbPfp.Parent then lbPfp.Image = content end
                end)
            end)

            -- Name label — suffix style: "Ares [VIP]" / "Ares [Legend]" / "Ares [Premium]"
            -- Only if user has no hardcoded or custom /title tag.
            local lbHasTag = (uid == CREATOR_ID or uid == OWNER_ID
                or CUTE_IDS[uid] or HELLGOD_IDS[uid]
                or VIP_IDS[uid] or GOD_IDS[uid]
                or DADDY_IDS[uid] or REAPER_IDS[uid]
                or PAPA_MVP_IDS[uid] or CustomTitles[uid])
            local lbTitleType = getFollowerTitleTypeFromCount(count)
            local lbTitleColor
            if lbTitleType == "VIP" then
                lbTitleColor = "rgb(220,160,0)"
            elseif lbTitleType == "Legend" then
                lbTitleColor = "rgb(220,30,30)"
            elseif lbTitleType == "Premium" then
                lbTitleColor = "rgb(0,120,220)"
            end

            local nameLbl = Instance.new("TextLabel", row)
            nameLbl.Size = UDim2.new(1, -140, 1, 0)
            nameLbl.Position = UDim2.new(0, 72, 0, 0)
            nameLbl.BackgroundTransparency = 1
            nameLbl.RichText = true
            nameLbl.TextColor3 = Color3.fromRGB(0, 0, 0)
            nameLbl.Font = Enum.Font.GothamBold
            nameLbl.TextSize = 13
            nameLbl.TextXAlignment = Enum.TextXAlignment.Left
            nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
            if lbTitleType and not lbHasTag and lbTitleColor then
                nameLbl.Text = displayName .. " <font color='" .. lbTitleColor .. "'>[" .. lbTitleType .. "]</font>"
            else
                nameLbl.Text = displayName
            end

            -- Follower count pill
            local countPill = Instance.new("TextLabel", row)
            countPill.Size = UDim2.new(0, 62, 0, 22)
            countPill.Position = UDim2.new(1, -68, 0.5, -11)
            countPill.BackgroundColor3 = Color3.fromRGB(255, 230, 240)
            countPill.BackgroundTransparency = 0.0
            countPill.BorderSizePixel = 0
            countPill.Text = tostring(count) .. " 👥"
            countPill.TextColor3 = Color3.fromRGB(225, 48, 108)
            countPill.Font = Enum.Font.GothamBold
            countPill.TextSize = 11
            countPill.TextXAlignment = Enum.TextXAlignment.Center
            Instance.new("UICorner", countPill).CornerRadius = UDim.new(0, 11)
        end
    end)
end

-- ============================================================
-- WINNER BOARD — Trophy leaderboard from Firebase (/trophies)
-- Shows all-time trophy winners and this server's session results.
-- ============================================================
function RefreshWinnerBoard()
    for _, child in pairs(WinnerLog:GetChildren()) do
        if not child:IsA("UIListLayout") then child:Destroy() end
    end

    -- Session results header (gameBotWinCounts may be empty on join)
    local sessionHeader = Instance.new("TextLabel", WinnerLog)
    sessionHeader.Size = UDim2.new(1, 0, 0, 22)
    sessionHeader.BackgroundTransparency = 1
    sessionHeader.Text = "🎮  This Server — Game Session"
    sessionHeader.TextColor3 = Color3.fromRGB(50, 180, 100)
    sessionHeader.Font = Enum.Font.GothamBold
    sessionHeader.TextSize = 12
    sessionHeader.TextXAlignment = Enum.TextXAlignment.Left

    local sessionWinners = {}
    for name, count in pairs(gameBotWinCounts) do
        table.insert(sessionWinners, {name = name, count = count})
    end
    table.sort(sessionWinners, function(a, b) return a.count > b.count end)

    if #sessionWinners == 0 then
        local noGame = Instance.new("TextLabel", WinnerLog)
        noGame.Size = UDim2.new(1, 0, 0, 26)
        noGame.BackgroundTransparency = 1
        noGame.Text = "No game played yet. Type /gamebot to start!"
        noGame.TextColor3 = Color3.fromRGB(160, 160, 160)
        noGame.Font = Enum.Font.Gotham
        noGame.TextSize = 11
        noGame.TextXAlignment = Enum.TextXAlignment.Left
    else
        for i, w in ipairs(sessionWinners) do
            local sRow = Instance.new("Frame", WinnerLog)
            sRow.Size = UDim2.new(1, -4, 0, 32)
            sRow.BackgroundColor3 = Color3.fromRGB(240, 255, 245)
            sRow.BackgroundTransparency = 0.0
            sRow.BorderSizePixel = 0
            Instance.new("UICorner", sRow).CornerRadius = UDim.new(0, 8)
            local sn = Instance.new("TextLabel", sRow)
            sn.Size = UDim2.new(1, -70, 1, 0)
            sn.Position = UDim2.new(0, 10, 0, 0)
            sn.BackgroundTransparency = 1
            sn.Text = (i == 1 and "🥇 " or i == 2 and "🥈 " or "🥉 ") .. w.name
            sn.TextColor3 = Color3.fromRGB(0, 0, 0)
            sn.Font = Enum.Font.GothamBold
            sn.TextSize = 12
            sn.TextXAlignment = Enum.TextXAlignment.Left
            local sc = Instance.new("TextLabel", sRow)
            sc.Size = UDim2.new(0, 60, 1, 0)
            sc.Position = UDim2.new(1, -64, 0, 0)
            sc.BackgroundTransparency = 1
            sc.Text = w.count .. " wins"
            sc.TextColor3 = Color3.fromRGB(50, 180, 100)
            sc.Font = Enum.Font.GothamBold
            sc.TextSize = 11
            sc.TextXAlignment = Enum.TextXAlignment.Right
        end
    end

    -- Divider
    local divider = Instance.new("Frame", WinnerLog)
    divider.Size = UDim2.new(1, 0, 0, 1)
    divider.BackgroundColor3 = Color3.fromRGB(219, 219, 219)
    divider.BorderSizePixel = 0

    -- All-time trophy leaderboard header
    local allTimeHeader = Instance.new("TextLabel", WinnerLog)
    allTimeHeader.Size = UDim2.new(1, 0, 0, 22)
    allTimeHeader.BackgroundTransparency = 1
    allTimeHeader.Text = "🏆  All-Time Trophy Leaders"
    allTimeHeader.TextColor3 = Color3.fromRGB(200, 160, 0)
    allTimeHeader.Font = Enum.Font.GothamBold
    allTimeHeader.TextSize = 12
    allTimeHeader.TextXAlignment = Enum.TextXAlignment.Left

    local loadLbl = Instance.new("TextLabel", WinnerLog)
    loadLbl.Size = UDim2.new(1, 0, 0, 24)
    loadLbl.BackgroundTransparency = 1
    loadLbl.Text = "Loading trophy data..."
    loadLbl.TextColor3 = Color3.fromRGB(180, 180, 180)
    loadLbl.Font = Enum.Font.Gotham
    loadLbl.TextSize = 11

    task.spawn(function()
        local req = syn and syn.request or http and http.request or request
        if not req then
            if loadLbl and loadLbl.Parent then loadLbl.Text = "No HTTP request available." end
            return
        end
        local allTrophies = {}
        pcall(function()
            local res = req({ Url = TROPHIES_URL .. ".json", Method = "GET" })
            if res and res.Success and res.Body ~= "null" then
                local ok, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
                if ok and type(data) == "table" then
                    for uidStr, tdata in pairs(data) do
                        local uid = tonumber(uidStr)
                        if uid and type(tdata) == "table" then
                            table.insert(allTrophies, {
                                uid = uid,
                                count = tonumber(tdata.count) or 0,
                                displayName = tdata.displayName or ("User " .. uidStr)
                            })
                        end
                    end
                end
            end
        end)
        table.sort(allTrophies, function(a, b) return a.count > b.count end)

        if loadLbl and loadLbl.Parent then loadLbl:Destroy() end
        for _, child in pairs(WinnerLog:GetChildren()) do
            if not child:IsA("UIListLayout") and child.Text and child.Text == "Loading trophy data..." then
                child:Destroy()
            end
        end

        if #allTrophies == 0 then
            local emptyLbl = Instance.new("TextLabel", WinnerLog)
            emptyLbl.Size = UDim2.new(1, 0, 0, 28)
            emptyLbl.BackgroundTransparency = 1
            emptyLbl.Text = "No trophies yet — play a game to earn your first! 🏆"
            emptyLbl.TextColor3 = Color3.fromRGB(160, 160, 160)
            emptyLbl.Font = Enum.Font.Gotham
            emptyLbl.TextSize = 11
            return
        end

        for rank, entry in ipairs(allTrophies) do
            local row = Instance.new("Frame", WinnerLog)
            row.Size = UDim2.new(1, -4, 0, 44)
            row.BackgroundColor3 = Color3.fromRGB(255, 250, 230)
            row.BackgroundTransparency = 0.0
            row.BorderSizePixel = 0
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)
            local rStroke = Instance.new("UIStroke", row)
            rStroke.Color = Color3.fromRGB(255, 215, 0)
            rStroke.Thickness = 1

            local rankLbl = Instance.new("TextLabel", row)
            rankLbl.Size = UDim2.new(0, 26, 1, 0)
            rankLbl.Position = UDim2.new(0, 4, 0, 0)
            rankLbl.BackgroundTransparency = 1
            rankLbl.Text = rank == 1 and "🥇" or rank == 2 and "🥈" or rank == 3 and "🥉" or tostring(rank)
            rankLbl.TextColor3 = Color3.fromRGB(200, 150, 0)
            rankLbl.Font = Enum.Font.GothamBold
            rankLbl.TextSize = 14
            rankLbl.TextXAlignment = Enum.TextXAlignment.Center

            local wPfp = Instance.new("ImageButton", row)
            wPfp.Size = UDim2.new(0, 30, 0, 30)
            wPfp.Position = UDim2.new(0, 32, 0.5, -15)
            wPfp.BackgroundColor3 = Color3.fromRGB(220, 220, 220)
            wPfp.BorderSizePixel = 0
            wPfp.AutoButtonColor = false
            Instance.new("UICorner", wPfp).CornerRadius = UDim.new(1, 0)
            local captUid = entry.uid
            local captName = entry.displayName
            wPfp.MouseButton1Click:Connect(function()
                showProfilePage(captUid, captName, captName)
            end)
            task.spawn(function()
                pcall(function()
                    local c, r = Players:GetUserThumbnailAsync(entry.uid, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
                    if r and wPfp and wPfp.Parent then wPfp.Image = c end
                end)
            end)

            local nameLbl = Instance.new("TextLabel", row)
            nameLbl.Size = UDim2.new(1, -130, 1, 0)
            nameLbl.Position = UDim2.new(0, 68, 0, 0)
            nameLbl.BackgroundTransparency = 1
            nameLbl.Text = entry.displayName
            nameLbl.TextColor3 = Color3.fromRGB(0, 0, 0)
            nameLbl.Font = Enum.Font.GothamBold
            nameLbl.TextSize = 12
            nameLbl.TextXAlignment = Enum.TextXAlignment.Left
            nameLbl.TextTruncate = Enum.TextTruncate.AtEnd

            local tPill = Instance.new("TextLabel", row)
            tPill.Size = UDim2.new(0, 58, 0, 20)
            tPill.Position = UDim2.new(1, -62, 0.5, -10)
            tPill.BackgroundColor3 = Color3.fromRGB(255, 230, 100)
            tPill.BackgroundTransparency = 0.0
            tPill.BorderSizePixel = 0
            tPill.Text = "🏆 " .. tostring(entry.count)
            tPill.TextColor3 = Color3.fromRGB(150, 80, 0)
            tPill.Font = Enum.Font.GothamBold
            tPill.TextSize = 11
            tPill.TextXAlignment = Enum.TextXAlignment.Center
            Instance.new("UICorner", tPill).CornerRadius = UDim.new(0, 10)
        end
    end)
end

-- ============================================================
-- GAMEBOT — AresBot mini-game system
-- Medium difficulty: Fast Math | Unscramble | Guess Number | Fill Blank
-- Only the host client (who typed /gamebot) generates & judges questions.
-- All players see questions/results via normal Firebase chat sync.
-- Winner of each round earns 1 🏆 trophy stored in Firebase.
-- ============================================================

local function gameBotSendSystem(text)
    local ts = string.format("%012d", os.time()) .. math.random(100, 999)
    local pkt = {
        Sender = "SYSTEM", SenderUid = 0, Content = text,
        Server = JobId, IsSystem = true, IsAutoClean = false
    }
    local req = syn and syn.request or http and http.request or request
    if req then
        pcall(function()
            req({ Url = DATABASE_URL .. "/" .. ts .. ".json", Method = "PUT", Body = HttpService:JSONEncode(pkt) })
        end)
    end
end

local function gameBotAwardTrophy(winnerName, winnerUid)
    task.spawn(function()
        pcall(function()
            local req = syn and syn.request or http and http.request or request
            if not req then return end
            local res = req({ Url = TROPHIES_URL .. "/" .. tostring(winnerUid) .. ".json", Method = "GET" })
            local currentCount = 0
            if res and res.Success and res.Body ~= "null" then
                local ok, td = pcall(HttpService.JSONDecode, HttpService, res.Body)
                if ok and type(td) == "table" then currentCount = tonumber(td.count) or 0 end
            end
            currentCount = currentCount + 1
            req({ Url = TROPHIES_URL .. "/" .. tostring(winnerUid) .. ".json", Method = "PUT",
                Body = HttpService:JSONEncode({ count = currentCount, displayName = winnerName }) })
            trophyCache[winnerUid] = currentCount
        end)
    end)
end

-- Question generators (medium difficulty)
local _gbMathOps  = {"+", "-", "*"}
local function gameBotMathQ()
    local op = _gbMathOps[math.random(1, 3)]
    local a, b, ans
    if op == "+" then
        a = math.random(12, 89); b = math.random(12, 89); ans = a + b
    elseif op == "-" then
        a = math.random(30, 99); b = math.random(1, a - 10); ans = a - b
    else
        a = math.random(3, 15); b = math.random(3, 15); ans = a * b
    end
    return "What is " .. a .. " " .. op .. " " .. b .. "?", tostring(ans)
end

local _gbRbxWords = {
    "roblox","avatar","studio","script","builder","castle","zombie",
    "dragon","island","portal","server","shield","battle","forest","mining"
}
local function gameBotScrambleQ()
    local word = _gbRbxWords[math.random(1, #_gbRbxWords)]
    local chars = {}
    for c in word:gmatch(".") do table.insert(chars, c) end
    for i = #chars, 2, -1 do
        local j = math.random(1, i); chars[i], chars[j] = chars[j], chars[i]
    end
    if table.concat(chars) == word then chars[1], chars[2] = chars[2], chars[1] end
    return "Unscramble: " .. table.concat(chars):upper() .. " (Roblox word)", word
end

local function gameBotGuessQ()
    local num = math.random(1, 50)
    local hint = num > 25 and "above 25" or "25 or below"
    return "Guess the number! (1-50, hint: it is " .. hint .. ")", tostring(num)
end

local _gbFillWords = {
    "ROBLOX","AVATAR","STUDIO","SCRIPT","SPAWN","CASTLE",
    "DRAGON","ISLAND","PORTAL","TROPHY","PLAYER","BADGE",
    "SWORD","ARMOR","QUEST","BUILDER","ZOMBIE"
}
local function gameBotFillQ()
    local word = _gbFillWords[math.random(1, #_gbFillWords)]
    local pos = math.random(2, #word - 1)
    local blanked = word:sub(1, pos - 1) .. "_" .. word:sub(pos + 1)
    return "Fill the blank: " .. blanked, word:lower()
end

local function gameBotMakeQuestion()
    if gameBotGame == "math"       then return gameBotMathQ()
    elseif gameBotGame == "unscramble" then return gameBotScrambleQ()
    elseif gameBotGame == "guess"  then return gameBotGuessQ()
    elseif gameBotGame == "fill"   then return gameBotFillQ()
    end
    return "Unknown game", "?"
end

local function gameBotNextRound()
    gameBotRound = gameBotRound + 1
    if gameBotRound > gameBotTotal then
        -- Game over — find session champion and award 1 permanent trophy
        gameBotActive  = false
        gameBotIsHost  = false
        gameBotAnswer  = nil
        local winners = {}
        for name, count in pairs(gameBotWinCounts) do
            table.insert(winners, { name = name, count = count })
        end
        table.sort(winners, function(a, b) return a.count > b.count end)
        local resultStr = "🎮 AresBot — Game Over! Final Results: "
        for i, w in ipairs(winners) do
            if i <= 3 then resultStr = resultStr .. (i == 1 and "🥇" or i == 2 and "🥈" or "🥉") .. w.name .. "(" .. w.count .. ") " end
        end
        if #winners == 0 then resultStr = resultStr .. "No one answered!" end
        task.delay(1.5, function() gameBotSendSystem(resultStr) end)

        -- Award 1 REAL permanent trophy to the session champion only
        if #winners > 0 then
            local champion = winners[1]
            -- Find champion's UID from gameBotWinCounts uid map
            local champUid = gameBotWinnerUids[champion.name] or 0
            if champUid ~= 0 then
                task.delay(2.5, function()
                    gameBotAwardTrophy(champion.name, champUid)
                    gameBotSendSystem(
                        "🏆 " .. champion.name .. " wins the session with " .. champion.count
                        .. " round win" .. (champion.count ~= 1 and "s" or "")
                        .. " and earns 1 REAL permanent trophy! 🎉"
                    )
                end)
            end
        end
        return
    end
    local q, a = gameBotMakeQuestion()
    gameBotAnswer = string.lower(tostring(a))
    task.delay(1.2, function()
        gameBotSendSystem("🎮 [AresBot] Round " .. gameBotRound .. "/" .. gameBotTotal .. " — " .. q)
    end)
end

local function gameBotStartGame(gameType)
    gameBotActive    = true
    gameBotIsHost    = true
    gameBotGame      = gameType
    gameBotRound     = 0
    gameBotWinCounts = {}
    gameBotWinnerUids = {}
    gameBotAnswer    = nil
    local names = {
        math       = "➕ Fast Math",
        unscramble = "🔤 Unscramble",
        guess      = "🔢 Guess the Number",
        fill       = "🔡 Fill the Blank"
    }
    local gameName = names[gameType] or gameType
    gameBotSendSystem("🎮 AresBot starting: " .. gameName .. "! 10 rounds. Player with most round wins gets 1 🏆 permanent trophy!")
    task.delay(1.8, function() gameBotNextRound() end)
end

-- ============================================================
-- FRIENDS LOGIC
-- ============================================================
local function GetPlaceName(id)
    local success, info = pcall(function() return MarketplaceService:GetProductInfo(id) end)
    return success and info.Name or "Unknown Game"
end

function RefreshFriends()
    for _, child in pairs(FriendsLog:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
    local success, friends = pcall(function() return LocalPlayer:GetFriendsOnline(200) end)
    if success and friends then
        for _, friend in pairs(friends) do
            local fFrame = Instance.new("Frame", FriendsLog)
            fFrame.Size = UDim2.new(1, -5, 0, 60)
            fFrame.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
            fFrame.BackgroundTransparency = 0.0
            Instance.new("UICorner", fFrame).CornerRadius = UDim.new(0, 10)
            local fStroke = Instance.new("UIStroke", fFrame)
            fStroke.Color = Color3.fromRGB(219, 219, 219)
            fStroke.Thickness = 1

            local pfp = Instance.new("ImageButton", fFrame)
            pfp.Size = UDim2.new(0, 40, 0, 40)
            pfp.Position = UDim2.new(0, 8, 0.5, 0)
            pfp.AnchorPoint = Vector2.new(0, 0.5)
            pfp.BackgroundTransparency = 1
            pfp.AutoButtonColor = false
            Instance.new("UICorner", pfp).CornerRadius = UDim.new(1, 0)
            pfp.MouseButton1Click:Connect(function()
                showProfilePage(friend.VisitorId, friend.DisplayName, friend.UserName or friend.DisplayName)
            end)
            task.spawn(function()
                local content, ready = Players:GetUserThumbnailAsync(friend.VisitorId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
                if ready then pfp.Image = content end
            end)

            local dot = Instance.new("Frame", fFrame)
            dot.Size = UDim2.new(0, 10, 0, 10)
            dot.Position = UDim2.new(0, 38, 0.5, 8)
            dot.BackgroundColor3 = Color3.fromRGB(0, 220, 80)
            Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

            local fName = Instance.new("TextLabel", fFrame)
            fName.Size = UDim2.new(1, -165, 0, 20)
            fName.Position = UDim2.new(0, 56, 0, 9)
            fName.Text = friend.DisplayName
            fName.TextColor3 = Color3.fromRGB(0, 0, 0)
            fName.Font = Enum.Font.GothamBold
            fName.TextSize = 13
            fName.TextXAlignment = Enum.TextXAlignment.Left
            fName.BackgroundTransparency = 1

            local fPresence = Instance.new("TextLabel", fFrame)
            fPresence.Size = UDim2.new(1, -165, 0, 16)
            fPresence.Position = UDim2.new(0, 56, 0, 30)
            fPresence.TextColor3 = Color3.fromRGB(100, 100, 100)
            fPresence.Font = Enum.Font.Gotham
            fPresence.TextSize = 11
            fPresence.TextXAlignment = Enum.TextXAlignment.Left
            fPresence.BackgroundTransparency = 1
            task.spawn(function()
                local gameName = GetPlaceName(friend.PlaceId)
                fPresence.Text = "[Game] " .. gameName
            end)

            local JoinBtn = Instance.new("TextButton", fFrame)
            JoinBtn.Size = UDim2.new(0, 48, 0, 24)
            JoinBtn.Position = UDim2.new(1, -54, 0.5, -12)
            JoinBtn.Text = "JOIN"
            JoinBtn.BackgroundColor3 = Color3.fromRGB(0, 160, 80)
            JoinBtn.Font = Enum.Font.GothamBold
            JoinBtn.TextColor3 = Color3.new(1, 1, 1)
            JoinBtn.TextSize = 11
            Instance.new("UICorner", JoinBtn).CornerRadius = UDim.new(0, 6)

            local InviteBtn = Instance.new("TextButton", fFrame)
            InviteBtn.Size = UDim2.new(0, 52, 0, 24)
            InviteBtn.Position = UDim2.new(1, -110, 0.5, -12)
            InviteBtn.Text = "INVITE"
            InviteBtn.BackgroundColor3 = Color3.fromRGB(60, 80, 200)
            InviteBtn.Font = Enum.Font.GothamBold
            InviteBtn.TextColor3 = Color3.new(1, 1, 1)
            InviteBtn.TextSize = 11
            Instance.new("UICorner", InviteBtn).CornerRadius = UDim.new(0, 6)

            JoinBtn.MouseButton1Click:Connect(function()
                TeleportService:TeleportToPlaceInstance(friend.PlaceId, friend.GameId, LocalPlayer)
            end)
            InviteBtn.MouseButton1Click:Connect(function()
                pcall(function() SocialService:PromptGameInvite(LocalPlayer) end)
            end)
        end
    end
end

-- ============================================================
-- TAB SWITCHING — updated to support Leaderboard and Aura tab
-- ============================================================
local function SetActiveTab(page, btn)
    ChatPage.Visible = false
    FriendsPage.Visible = false
    AdminPage.Visible = false
    LeaderboardPage.Visible = false
    MusicPage.Visible = false
    WinnerPage.Visible = false
    Input.Parent.Visible = (page == ChatPage)
    ActivePageName = (page == FriendsPage and "Friends") or (page == LeaderboardPage and "Top") or (page == AdminPage and "Admin") or (page == MusicPage and "Music") or (page == WinnerPage and "Winners") or "Chat"
    if page == ChatPage then
        if PrivateTargetId then
            Input.PlaceholderText = "[PVT] " .. tostring(PrivateTargetName or "User") .. "..."
        else
            Input.PlaceholderText = "* Type a message..."
            Input.Position = UDim2.new(0, 8, 0, 0)
            Input.Size = UDim2.new(1, -82, 1, 0)
            InputArea.BackgroundColor3 = Color3.fromRGB(250, 250, 250)
        end
    end

    local allBtns = {ChatTabBtn, FriendsTabBtn, LeaderboardTabBtn, WinnerTabBtn}
    if AdminTabBtn then table.insert(allBtns, AdminTabBtn) end
    if MusicTabBtn then table.insert(allBtns, MusicTabBtn) end
    for _, b in pairs(allBtns) do
        b.BackgroundTransparency = 0.0
        b.BackgroundColor3 = Color3.fromRGB(239, 239, 239)
        b.TextColor3 = Color3.fromRGB(120, 120, 120)
    end

    page.Visible = true
    btn.BackgroundColor3 = Color3.fromRGB(225, 48, 108)
    btn.BackgroundTransparency = 0.0
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
end

ChatTabBtn.MouseButton1Click:Connect(function() SetActiveTab(ChatPage, ChatTabBtn) end)
FriendsTabBtn.MouseButton1Click:Connect(function() SetActiveTab(FriendsPage, FriendsTabBtn) RefreshFriends() end)
LeaderboardTabBtn.MouseButton1Click:Connect(function() SetActiveTab(LeaderboardPage, LeaderboardTabBtn) RefreshLeaderboard() end)
WinnerTabBtn.MouseButton1Click:Connect(function() SetActiveTab(WinnerPage, WinnerTabBtn) RefreshWinnerBoard() end)
if AdminTabBtn then
    AdminTabBtn.MouseButton1Click:Connect(function() SetActiveTab(AdminPage, AdminTabBtn) BuildAdminPanel() end)
end
if MusicTabBtn then
    MusicTabBtn.MouseButton1Click:Connect(function() SetActiveTab(MusicPage, MusicTabBtn) end)
end

ChatTabBtn.BackgroundTransparency = 0.0
ChatTabBtn.BackgroundColor3 = Color3.fromRGB(225, 48, 108)
ChatTabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)

-- ============================================================
-- NOTIFICATION FUNCTION
-- ============================================================
local function createNotification(sender, message, isPrivate, isSystem, senderUid, isAutoClean)
    if isAutoClean then return end
    if Main.Visible or activeNotification then return end

    local nFrame = Instance.new("Frame", NotifContainer)
    nFrame.Size = UDim2.new(1, 0, 0, 66)
    nFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    nFrame.BackgroundTransparency = 0.0
    nFrame.Position = UDim2.new(0, 0, -1.5, 0)
    Instance.new("UICorner", nFrame).CornerRadius = UDim.new(0, 12)
    local nStroke = Instance.new("UIStroke", nFrame)
    nStroke.Color = Color3.fromRGB(225, 48, 108)
    nStroke.Thickness = 1.2
    activeNotification = nFrame

    local pfpFrame = Instance.new("Frame", nFrame)
    pfpFrame.Size = UDim2.new(0, 42, 0, 42)
    pfpFrame.Position = UDim2.new(0, 12, 0.5, 0)
    pfpFrame.AnchorPoint = Vector2.new(0, 0.5)
    pfpFrame.BackgroundColor3 = Color3.fromRGB(220, 220, 220)
    pfpFrame.BorderSizePixel = 0
    Instance.new("UICorner", pfpFrame).CornerRadius = UDim.new(1, 0)

    if isSystem then
        local chickLabel = Instance.new("TextLabel", pfpFrame)
        chickLabel.Size = UDim2.new(1, 0, 1, 0)
        chickLabel.BackgroundTransparency = 1
        chickLabel.Text = "🐥"
        chickLabel.Font = Enum.Font.GothamBold
        chickLabel.TextSize = 22
        chickLabel.TextXAlignment = Enum.TextXAlignment.Center
        chickLabel.TextYAlignment = Enum.TextYAlignment.Center
    else
        local pfp = Instance.new("ImageLabel", pfpFrame)
        pfp.Size = UDim2.new(1, 0, 1, 0)
        pfp.BackgroundTransparency = 1
        Instance.new("UICorner", pfp).CornerRadius = UDim.new(1, 0)
        if senderUid and senderUid ~= 0 then
            task.spawn(function()
                local content, isReady = Players:GetUserThumbnailAsync(senderUid, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
                if isReady then pfp.Image = content end
            end)
        end
    end

    local nText = Instance.new("TextLabel", nFrame)
    nText.Size = UDim2.new(1, -68, 1, -8)
    nText.Position = UDim2.new(0, 62, 0, 4)
    nText.BackgroundTransparency = 1
    nText.RichText = true
    -- Truncate message preview to 60 chars so it never overflows the notification bar
    local preview = SafeEncodeMsg(message)
    if #preview > 60 then preview = string.sub(preview, 1, 57) .. "..." end
    nText.Text = string.format(
        "<b><font color='rgb(0,0,0)'>%s</font></b>\n<font size='12' color='rgb(80,80,80)'>%s</font>",
        SafeEncodeMsg(sender), preview
    )
    nText.TextColor3 = Color3.fromRGB(0, 0, 0)
    nText.TextSize = 13
    nText.Font = Enum.Font.Gotham
    nText.TextXAlignment = Enum.TextXAlignment.Left
    nText.TextWrapped = false
    nText.TextTruncate = Enum.TextTruncate.AtEnd

    TweenService:Create(nFrame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = UDim2.new(0, 0, 0, 5)}):Play()
    task.delay(7, function()
        if nFrame and nFrame.Parent then
            local fadeOut = TweenService:Create(nFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {Position = UDim2.new(0, 0, -1.5, 0), BackgroundTransparency = 1})
            fadeOut:Play()
            fadeOut.Completed:Connect(function() nFrame:Destroy() activeNotification = nil end)
        end
    end)
end

-- ============================================================
-- BUBBLE LOGIC (PRESERVED)
-- ============================================================
local function createBubble(player, text, isPrivate)
    -- MUTE CHECK: do not show bubble for muted players
    if MutedPlayers[player.UserId] then return end
    local character = player.Character
    if not character or not character:FindFirstChild("Head") then return end
    local head = character.Head
    local existing = head:FindFirstChild("AresBubble")
    if existing then existing:Destroy() end
    local bGui = Instance.new("BillboardGui", head)
    bGui.Name = "AresBubble"
    bGui.Adornee = head
    bGui.Size = UDim2.new(0, math.clamp(#text * 14, 80, 320), 0, 54)
    bGui.StudsOffset = Vector3.new(0, 4, 0)
    bGui.MaxDistance = 80
    local bFrame = Instance.new("Frame", bGui)
    bFrame.Size = UDim2.new(1, 0, 1, 0)
    bFrame.BackgroundColor3 = isPrivate and Color3.fromRGB(255, 230, 245) or Color3.fromRGB(255, 255, 255)
    bFrame.BackgroundTransparency = 0.1
    Instance.new("UICorner", bFrame).CornerRadius = UDim.new(0, 14)
    local bStroke = Instance.new("UIStroke", bFrame)
    bStroke.Color = isPrivate and Color3.fromRGB(225, 48, 108) or Color3.fromRGB(200, 200, 200)
    bStroke.Thickness = 1.2
    local bText = Instance.new("TextLabel", bFrame)
    bText.Size = UDim2.new(1, -16, 1, -10)
    bText.Position = UDim2.new(0.5, 0, 0.5, 0)
    bText.AnchorPoint = Vector2.new(0.5, 0.5)
    bText.BackgroundTransparency = 1
    bText.Text = SafeEncodeMsg(text)
    bText.TextColor3 = Color3.fromRGB(0, 0, 0)
    bText.Font = Enum.Font.GothamMedium
    bText.TextSize = 16
    bText.TextWrapped = true
    task.delay(9, function() if bGui and bGui.Parent then bGui:Destroy() end end)
end

-- ============================================================
-- DRAGGING (PRESERVED) — main panel respects isGuiLocked
-- When isGuiLocked is true, the header drag is blocked.
-- ============================================================
local function MakeDraggable(UI, DragTrigger)
    local Dragging, DragStart, StartPos
    DragTrigger.InputBegan:Connect(function(input)
        -- Block dragging when GUI is locked
        if isGuiLocked then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            Dragging = true
            DragStart = input.Position
            StartPos = UI.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then Dragging = false end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if isGuiLocked then Dragging = false return end
        if Dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local Delta = input.Position - DragStart
            UI.Position = UDim2.new(StartPos.X.Scale, StartPos.X.Offset + Delta.X, StartPos.Y.Scale, StartPos.Y.Offset + Delta.Y)
        end
    end)
end

MakeDraggable(Main, Header)

-- ============================================================
-- TOGGLE BUTTON DRAG — drag-aware so a quick tap still
-- toggles the panel, but a real drag just repositions it.
-- toggleDragMoved is read by the MouseButton1Click handler below.
-- When isGuiLocked is true, the toggle button cannot be dragged.
-- ============================================================
local toggleDragMoved = false
do
    local tbDragging, tbDragStart, tbStartPos
    ToggleBtn.InputBegan:Connect(function(input)
        -- Block toggle button dragging when GUI is locked
        if isGuiLocked then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            tbDragging  = true
            toggleDragMoved = false
            tbDragStart = input.Position
            tbStartPos  = ToggleBtn.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    tbDragging = false
                end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if isGuiLocked then tbDragging = false return end
        if tbDragging and (
            input.UserInputType == Enum.UserInputType.MouseMovement
         or input.UserInputType == Enum.UserInputType.Touch
        ) then
            local delta = input.Position - tbDragStart
            if delta.Magnitude > 5 then
                toggleDragMoved = true
                ToggleBtn.Position = UDim2.new(
                    tbStartPos.X.Scale, tbStartPos.X.Offset + delta.X,
                    tbStartPos.Y.Scale, tbStartPos.Y.Offset + delta.Y
                )
            end
        end
    end)
end

-- ============================================================
-- MESSAGE COLOR HELPER
-- ============================================================
local function GetUserColor(name)
    local hash = 0
    for i = 1, #name do
        hash = (hash * 31 + string.byte(name, i)) % 360
    end
    -- Exclude hues near red (0°/360°) and near pink (330°-360°) by
    -- remapping 0-359 across a rainbow that avoids the red cluster.
    -- We shift by 40° and scale so the full palette is spread evenly.
    local hue = ((hash * 7 + 40) % 360) / 360
    return Color3.fromHSV(hue, 0.72, 1.0)
end

-- ============================================================
-- SYSTEM MESSAGE HELPER
-- Strips any legacy [ARES_BADGE:...] markers from old join
-- messages stored in Firebase (no-op for new messages).
-- ============================================================
local function applySystemBadgeImage(textButton, safeMsg)
    -- Strip legacy badge markers left by previous script versions.
    local cleanMsg = safeMsg:gsub("%s*%[ARES_BADGE:%d+%]%s*", "")
    return cleanMsg
end

-- ============================================================
-- TRIM MESSAGES
-- Uses sortedMessageKeys so we always remove the genuinely
-- oldest messages — never random ones.
-- ============================================================
local function trimMessages(messageKeys, buttonMap)
    messageKeys = messageKeys or sortedMessageKeys
    buttonMap = buttonMap or keyToButton
    local excess = #messageKeys - MAX_MESSAGES
    if excess <= 0 then return end

    local req = syn and syn.request or http and http.request or request

    for i = 1, excess do
        local oldestKey = messageKeys[1]
        if not oldestKey then break end

        table.remove(messageKeys, 1)
        local btn = buttonMap[oldestKey]
        buttonMap[oldestKey] = nil

        if btn and btn.Parent then
            TweenService:Create(btn, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                BackgroundTransparency = 1,
                TextTransparency = 1
            }):Play()
            task.delay(0.26, function()
                if btn and btn.Parent then
                    SpecialLabels[btn] = nil
                    NormalTitleLabels[btn] = nil
                    btn.Parent:Destroy()  -- destroy wrapperFrame (also destroys TextButton child)
                end
            end)
        end

        if req then
            local keyToDel = oldestKey
            task.spawn(function()
                pcall(function()
                    req({Url = DATABASE_URL .. "/" .. keyToDel .. ".json", Method = "DELETE"})
                end)
            end)
        end
    end
end

-- ============================================================
-- ADD MESSAGE
-- TAP = REPLY  |  HOLD (0.6s) = TOGGLE PRIVATE CHAT
-- Instagram-style highlighting:
--   • Someone replied TO YOU  → green left-bar + highlighted bg
--   • You replied to someone  → blue left-bar + highlighted bg
-- FIX: reply quote is now a proper sub-frame (no more overlap)
-- ============================================================
function addMessage(displayName, msg, isSystem, order, senderUid, isPrivate, skipBubble, replyTo, targetLog)
    -- MUTE CHECK: skip rendering messages from muted players (GUI suppression)
    if not isSystem and MutedPlayers[senderUid] then return end

    local safeName  = SafeEncodeMsg(tostring(displayName or ""))
    local safeMsg   = SafeEncodeMsg(tostring(msg or ""))
    local safeReply = replyTo and SafeEncodeMsg(tostring(replyTo)) or nil

    -- Detect highlight conditions
    local myDisplayName = SafeEncodeMsg(RealDisplayName)
    local isReplyToMe = (not isSystem)
        and (safeReply ~= nil and safeReply ~= "")
        and string.find(string.lower(safeReply), string.lower(myDisplayName), 1, true) ~= nil
        and senderUid ~= RealUserId
    local isMyReply = (senderUid == RealUserId)
        and (safeReply ~= nil and safeReply ~= "")
        and (not isSystem)

    local renderLog = targetLog or ChatLog
    local activeMessageKeys = sortedMessageKeys
    local activeKeyToButton = keyToButton

    -- ============================================================
    -- PRE-COMPUTE sticker detection so we know whether to show pfp
    -- as a sibling (regular msg) or embed it in the bubble (sticker).
    -- ============================================================
    local rawMsg = tostring(msg or "")
    local stickerAssetId = string.match(rawMsg, "^%[STICKER:(%d+)%]$")

    -- ============================================================
    -- WRAPPER FRAME: UIListLayout manages this; TextButton inside it
    -- so TweenService can freely move TextButton for slide animation.
    -- ============================================================
    local wrapperFrame = Instance.new("Frame", renderLog)
    wrapperFrame.Size = UDim2.new(1, 0, 0, 0)
    wrapperFrame.AutomaticSize = Enum.AutomaticSize.Y
    wrapperFrame.BackgroundTransparency = 1
    wrapperFrame.BorderSizePixel = 0
    -- Local-only messages (order == 0) use nextLocalOrder() so they appear at the
    -- BOTTOM of the chat log, not at the top where LayoutOrder=0 would put them.
    wrapperFrame.LayoutOrder = (order and order ~= 0) and order or nextLocalOrder()
    wrapperFrame.ClipsDescendants = false

    -- ============================================================
    -- PROFILE PICTURE — placed as a SIBLING of TextButton inside
    -- wrapperFrame so it is completely outside the text area and
    -- can never overlap the display name or message text.
    -- Only created for real (non-system, non-sticker) messages.
    -- Sticker messages embed the pfp inside the bubble separately.
    -- ============================================================
    local pfpOffset = 0
    if not isSystem and senderUid and senderUid ~= 0 then
        pfpOffset = 34
        local pfpImg = Instance.new("ImageButton", wrapperFrame)
        pfpImg.Size                   = UDim2.new(0, 26, 0, 26)
        pfpImg.Position               = UDim2.new(0, 2, 0, 5)
        pfpImg.AnchorPoint            = Vector2.new(0, 0)
        pfpImg.BackgroundColor3       = Color3.fromRGB(220, 220, 220)
        pfpImg.BackgroundTransparency = 0.0
        pfpImg.BorderSizePixel        = 0
        pfpImg.AutoButtonColor        = false
        pfpImg.ZIndex                 = 3
        Instance.new("UICorner", pfpImg).CornerRadius = UDim.new(1, 0)
        pfpImg.MouseButton1Click:Connect(function()
            showProfilePage(senderUid, safeName, safeName)
        end)
        task.spawn(function()
            local ok, content, ready = pcall(function()
                return Players:GetUserThumbnailAsync(
                    senderUid,
                    Enum.ThumbnailType.HeadShot,
                    Enum.ThumbnailSize.Size48x48)
            end)
            if ok and ready then pfpImg.Image = content end
        end)
    end

    local TextButton = Instance.new("TextButton", wrapperFrame)
    TextButton.Size = UDim2.new(1, -pfpOffset, 0, 0)
    TextButton.AutomaticSize = Enum.AutomaticSize.Y
    TextButton.Position = UDim2.new(0, pfpOffset, 0, 0)
    TextButton.BackgroundTransparency = 0.0
    TextButton.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
    TextButton.RichText = true
    TextButton.TextWrapped = true
    TextButton.Font = Enum.Font.Gotham
    TextButton.TextSize = 13
    TextButton.TextColor3 = Color3.fromRGB(0, 0, 0)
    TextButton.TextXAlignment = Enum.TextXAlignment.Left
    TextButton.TextYAlignment = Enum.TextYAlignment.Top -- FIXED: Forces text to start strictly under the padding
    Instance.new("UICorner", TextButton).CornerRadius = UDim.new(0, 6)

    local pad = Instance.new("UIPadding", TextButton)
    pad.PaddingLeft   = UDim.new(0, 10)
    pad.PaddingRight  = UDim.new(0, 7)
    pad.PaddingTop    = UDim.new(0, 4)
    pad.PaddingBottom = UDim.new(0, 4)

    -- Reply highlights: light blue when I reply someone, green when someone replies to me
    if isMyReply then
        TextButton.BackgroundColor3 = Color3.fromRGB(220, 235, 255)
        TextButton.BackgroundTransparency = 0.0
    elseif isReplyToMe then
        TextButton.BackgroundColor3 = Color3.fromRGB(220, 248, 228)
        TextButton.BackgroundTransparency = 0.0
    end

    -- ============================================================
    -- STICKER DETECTION — already computed above (stickerAssetId).
    -- ============================================================

    -- ============================================================
    -- REPLY QUOTE SUB-FRAME — for NON-STICKER messages only.
    -- Sticker replies embed the quote box inside the bubble itself.
    -- ============================================================
    if safeReply and safeReply ~= "" and not stickerAssetId then
        -- Compact reply quote: single-line truncated, fixed 16px height
        local replyBoxH = 16
        pad.PaddingTop = UDim.new(0, replyBoxH + 4)  -- Push main text below reply box

        local replyBox = Instance.new("Frame", TextButton)
        replyBox.Size = UDim2.new(1, -4, 0, replyBoxH)
        replyBox.AutomaticSize = Enum.AutomaticSize.None
        replyBox.Position = UDim2.new(0, -3, 0, -(replyBoxH + 2))
        replyBox.BackgroundColor3 = Color3.fromRGB(30, 20, 55)
        replyBox.BackgroundTransparency = 0.35
        replyBox.BorderSizePixel = 0
        replyBox.ZIndex = 2
        replyBox.ClipsDescendants = true
        Instance.new("UICorner", replyBox).CornerRadius = UDim.new(0, 4)

        local replyBoxStroke = Instance.new("UIStroke", replyBox)
        replyBoxStroke.Color = Color3.fromRGB(100, 80, 160)
        replyBoxStroke.Thickness = 0.8
        replyBoxStroke.Transparency = 0.5

        local replyBoxPad = Instance.new("UIPadding", replyBox)
        replyBoxPad.PaddingLeft   = UDim.new(0, 5)
        replyBoxPad.PaddingRight  = UDim.new(0, 5)
        replyBoxPad.PaddingTop    = UDim.new(0, 1)
        replyBoxPad.PaddingBottom = UDim.new(0, 1)

        local replyBoxLabel = Instance.new("TextLabel", replyBox)
        replyBoxLabel.Size = UDim2.new(1, 0, 1, 0)
        replyBoxLabel.AutomaticSize = Enum.AutomaticSize.None
        replyBoxLabel.BackgroundTransparency = 1
        replyBoxLabel.RichText = true
        local displayReply = safeReply:gsub("%[STICKER:%d+%]", "🎭 Sticker")
        replyBoxLabel.Text = "↩ " .. displayReply
        replyBoxLabel.TextWrapped = false
        replyBoxLabel.TextTruncate = Enum.TextTruncate.AtEnd
        replyBoxLabel.Font = Enum.Font.Gotham
        replyBoxLabel.TextSize = 10
        replyBoxLabel.TextXAlignment = Enum.TextXAlignment.Left
        replyBoxLabel.TextColor3 = Color3.fromRGB(160, 140, 200)
        replyBoxLabel.ZIndex = 3
    end

    if stickerAssetId and not isSystem then
        -- ============================================================
        -- PREMIUM STICKER BUBBLE — name at top, sticker image below.
        -- Name label and image are ALWAYS separate children so they
        -- can never overlap, regardless of tag type or reply state.
        -- ============================================================
        local tagData = TagCache[senderUid] or {text = "", type = "Normal"}
        if tagData.type == "Normal" then
            local ct = CustomTitles[senderUid]
            if ct then
                local now = os.time()
                if ct.expiresAt and ct.expiresAt > now then
                    tagData = { text = "[" .. ct.title .. "] ", type = "CustomTitle", tagTitle = "[" .. ct.title .. "]", titleColor = ct.color }
                end
            end
        end
        local privTag  = isPrivate and "<font color='rgb(255,100,255)'>[PVT] </font>" or ""
        local color    = GetUserColor(safeName)
        local colorStr = string.format("rgb(%d,%d,%d)",
            math.clamp(math.floor(color.R*255), 0, 255),
            math.clamp(math.floor(color.G*255), 0, 255),
            math.clamp(math.floor(color.B*255), 0, 255))

        -- ============================================================
        -- STICKER BUBBLE LAYOUT — accommodates inline reply if present.
        -- No reply:  name(y=5) → sep(y=26) → sticker(y=29) = 110px
        -- With reply: replyBox(y=5,16px) → name(y=27) → sep(y=48) → sticker(y=52) = 133px
        -- All children are INSIDE the bubble so nothing overlaps.
        -- ============================================================
        local hasReplyInSticker = safeReply and safeReply ~= ""
        local replyBlockH       = hasReplyInSticker and 22 or 0
        local nameLabelY        = 5 + replyBlockH
        local sepY              = nameLabelY + 21
        local stickerImgY       = sepY + 3
        local stickerBubbleH    = stickerImgY + 76 + 5

        TextButton.AutomaticSize  = Enum.AutomaticSize.None
        TextButton.Size           = UDim2.new(1, 0, 0, stickerBubbleH)
        TextButton.BackgroundColor3       = Color3.fromRGB(245, 245, 245)
        TextButton.BackgroundTransparency = 0.0
        TextButton.Text           = ""  -- all content via child instances
        pad.PaddingTop    = UDim.new(0, 0)  -- managed by child positions
        pad.PaddingBottom = UDim.new(0, 0)
        pad.PaddingLeft   = UDim.new(0, 0)
        pad.PaddingRight  = UDim.new(0, 0)

        -- Inline reply quote — rendered INSIDE the bubble at the very top (no negative Y)
        if hasReplyInSticker then
            local rBox = Instance.new("Frame", TextButton)
            rBox.Size                    = UDim2.new(1, -14, 0, 16)
            rBox.Position                = UDim2.new(0, 7, 0, 5)
            rBox.BackgroundColor3        = Color3.fromRGB(30, 20, 55)
            rBox.BackgroundTransparency  = 0.35
            rBox.BorderSizePixel         = 0
            rBox.ZIndex                  = TextButton.ZIndex + 1
            rBox.ClipsDescendants        = true
            Instance.new("UICorner", rBox).CornerRadius = UDim.new(0, 4)
            local rBoxStroke = Instance.new("UIStroke", rBox)
            rBoxStroke.Color       = Color3.fromRGB(100, 80, 160)
            rBoxStroke.Thickness   = 0.8
            rBoxStroke.Transparency = 0.5
            local rBoxPad = Instance.new("UIPadding", rBox)
            rBoxPad.PaddingLeft   = UDim.new(0, 5)
            rBoxPad.PaddingRight  = UDim.new(0, 5)
            rBoxPad.PaddingTop    = UDim.new(0, 1)
            rBoxPad.PaddingBottom = UDim.new(0, 1)
            local rBoxLabel = Instance.new("TextLabel", rBox)
            rBoxLabel.Size = UDim2.new(1, 0, 1, 0)
            rBoxLabel.AutomaticSize = Enum.AutomaticSize.None
            rBoxLabel.BackgroundTransparency = 1
            rBoxLabel.RichText = true
            local displayReplySt = safeReply:gsub("%[STICKER:%d+%]", "🎭 Sticker")
            rBoxLabel.Text = "↩ " .. displayReplySt
            rBoxLabel.TextWrapped  = false
            rBoxLabel.TextTruncate = Enum.TextTruncate.AtEnd
            rBoxLabel.Font         = Enum.Font.Gotham
            rBoxLabel.TextSize     = 10
            rBoxLabel.TextXAlignment = Enum.TextXAlignment.Left
            rBoxLabel.TextColor3   = Color3.fromRGB(160, 140, 200)
            rBoxLabel.ZIndex       = TextButton.ZIndex + 2
        end

        -- Name row — sits below reply quote (or at top if no reply)
        local nameLabel = Instance.new("TextLabel", TextButton)
        nameLabel.Size              = UDim2.new(1, -14, 0, 18)
        nameLabel.Position          = UDim2.new(0, 7, 0, nameLabelY)
        nameLabel.BackgroundTransparency = 1
        nameLabel.RichText          = true
        nameLabel.TextXAlignment    = Enum.TextXAlignment.Left
        nameLabel.Font              = Enum.Font.Gotham
        nameLabel.TextSize          = 12
        nameLabel.TextColor3        = Color3.new(1, 1, 1)
        nameLabel.ZIndex            = TextButton.ZIndex + 1
        nameLabel.TextTruncate      = Enum.TextTruncate.AtEnd

        if tagData.type ~= "Normal" then
            -- RGB/special-tag user: initial render, RGB loop will keep it updated via stickerLabel
            nameLabel.Text = string.format("%s%s<font color='%s'><b>%s</b></font>",
                privTag, tagData.text, colorStr, safeName)
            SpecialLabels[TextButton] = {
                displayName  = safeName,
                msg          = "",  -- sticker image handles the visual; msg not used
                nameColor    = colorStr,
                isPrivate    = isPrivate,
                tagType      = tagData.type,
                tagTitle     = tagData.tagTitle,
                titleColor   = tagData.titleColor,  -- custom title colour
                replyTo      = nil,
                isSticker    = true,
                stickerLabel = nameLabel,
                senderUid    = senderUid,
            }
        else
            local _capStkBtn34  = TextButton
            local _capStkPvt34  = privTag
            local _capStkTag34  = tagData.text
            local _capStkClr34  = colorStr
            local _capStkNm34   = safeName
            local _capStkUid34  = senderUid
            local _capStkLbl34  = nameLabel
            nameLabel.Text = string.format("%s%s<font color='%s'><b>%s</b></font>",
                privTag, tagData.text, colorStr, safeName)
            -- Follower title for sticker nameLabel is handled by RGB heartbeat for Special labels.
            -- For Normal-tag stickers, register in NormalTitleLabels so heartbeat animates title.
            if tagData.type == "Normal" then
                onBadgeLoaded(_capStkUid34, function()
                    if _capStkLbl34 and _capStkLbl34.Parent then
                        local fTitleType = getFollowerTitleType(_capStkUid34)
                        if fTitleType then
                            -- Store in NormalTitleLabels so the heartbeat loop can animate it.
                            NormalTitleLabels[TextButton] = {
                                displayName = _capStkNm34,
                                msg         = safeMsg,
                                nameColor   = _capStkClr34,
                                isPrivate   = isPrivate,
                                senderUid   = _capStkUid34,
                                isSticker   = true,
                                stickerLabel = _capStkLbl34,
                            }
                        end
                    end
                end)
            end
        end

        -- Thin separator line between name and sticker image
        local sep = Instance.new("Frame", TextButton)
        sep.Size                    = UDim2.new(1, -14, 0, 1)
        sep.Position                = UDim2.new(0, 7, 0, sepY)
        sep.BackgroundColor3        = Color3.fromRGB(100, 60, 180)
        sep.BackgroundTransparency  = 0.6
        sep.BorderSizePixel         = 0
        sep.ZIndex                  = TextButton.ZIndex + 1

        -- Sticker image — below name row and sep, never overlaps
        local stickerImg = Instance.new("ImageLabel", TextButton)
        stickerImg.Size              = UDim2.new(0, 76, 0, 76)
        stickerImg.Position          = UDim2.new(0, 7, 0, stickerImgY)
        stickerImg.BackgroundTransparency = 1
        stickerImg.Image             = "rbxthumb://type=Asset&id=" .. stickerAssetId .. "&w=150&h=150"
        stickerImg.ScaleType         = Enum.ScaleType.Fit
        stickerImg.ZIndex            = TextButton.ZIndex + 1

        -- Premium light stroke on the bubble
        local stickerBubbleStroke = Instance.new("UIStroke", TextButton)
        stickerBubbleStroke.Color       = Color3.fromRGB(219, 219, 219)
        stickerBubbleStroke.Thickness   = 1.2
        stickerBubbleStroke.Transparency = 0.0

        if not skipBubble then
            for _, p in pairs(Players:GetPlayers()) do
                if p.UserId == senderUid then createBubble(p, "🎭 Sticker", isPrivate) end
            end
        end

    -- Main message text (NO inline reply line — it's in the sub-frame above)
    elseif isSystem then
        local systemMsgForDisplay = applySystemBadgeImage(TextButton, safeMsg)
        TextButton.Text = "<font color='rgb(200,100,0)'><b>[SYSTEM]</b></font> " .. systemMsgForDisplay
        TextButton.BackgroundColor3 = Color3.fromRGB(255, 248, 220)
    else
        local tagData = TagCache[senderUid] or {text = "", type = "Normal"}
        -- Re-check custom titles at display time (may have loaded after CachePlayerTags)
        if tagData.type == "Normal" then
            local ct = CustomTitles[senderUid]
            if ct then
                local now = os.time()
                if ct.expiresAt and ct.expiresAt > now then
                    tagData = {
                        text       = "[" .. ct.title .. "] ",
                        type       = "CustomTitle",
                        tagTitle   = "[" .. ct.title .. "]",
                        titleColor = ct.color
                    }
                end
            end
        end
        local privTag = isPrivate and "<font color='rgb(255,100,255)'>[PVT] </font>" or ""
        local color = GetUserColor(safeName)
        local colorStr = string.format("rgb(%d,%d,%d)",
            math.clamp(math.floor(color.R*255), 0, 255),
            math.clamp(math.floor(color.G*255), 0, 255),
            math.clamp(math.floor(color.B*255), 0, 255))

        if tagData.type ~= "Normal" then
            SpecialLabels[TextButton] = {
                displayName = safeName,
                msg         = safeMsg,
                nameColor   = colorStr,
                isPrivate   = isPrivate,
                tagType     = tagData.type,
                tagTitle    = tagData.tagTitle,
                titleColor  = tagData.titleColor,  -- custom title colour (red/white/yellow/black)
                replyTo     = safeReply,  -- kept for reference; NOT rendered in RGB loop
                senderUid   = senderUid,
            }
            fetchBadgeAsync(senderUid)
        else
            local _capturedBtn34    = TextButton
            local _capturedPriv34   = privTag
            local _capturedTag34    = tagData.text
            local _capturedColor34  = colorStr
            local _capturedName34   = safeName
            local _capturedMsg34    = safeMsg
            local _capturedUid34    = senderUid
            -- Set initial text (follower title loads async)
            _capturedBtn34.Text = string.format("%s%s<font color='%s'><b>%s</b></font>: %s",
                _capturedPriv34, _capturedTag34, _capturedColor34, _capturedName34, _capturedMsg34)
            onBadgeLoaded(_capturedUid34, function()
                if _capturedBtn34 and _capturedBtn34.Parent then
                    local fTitleType = getFollowerTitleType(_capturedUid34)
                    if fTitleType then
                        -- Register in NormalTitleLabels so heartbeat loop animates the title color.
                        NormalTitleLabels[_capturedBtn34] = {
                            displayName = _capturedName34,
                            msg         = _capturedMsg34,
                            nameColor   = _capturedColor34,
                            isPrivate   = isPrivate,
                            senderUid   = _capturedUid34,
                        }
                    end
                end
            end)
        end

        if not skipBubble then
            for _, p in pairs(Players:GetPlayers()) do
                if p.UserId == senderUid then createBubble(p, safeMsg, isPrivate) end
            end
        end
    end

    -- Track only real Firebase-keyed messages for trim logic.
    -- order == 0 means local-only (e.g. /clear confirm) — skip tracking.
    if order and order ~= 0 then
        local keyStr = tostring(order)
        local inserted = false
        local numOrder = tonumber(keyStr) or 0
        for i = #activeMessageKeys, 1, -1 do
            local existingNum = tonumber(activeMessageKeys[i]) or 0
            if numOrder >= existingNum then
                table.insert(activeMessageKeys, i + 1, keyStr)
                inserted = true
                break
            end
        end
        if not inserted then
            table.insert(activeMessageKeys, 1, keyStr)
        end
        activeKeyToButton[keyStr] = TextButton
        task.spawn(function()
            trimMessages(activeMessageKeys, activeKeyToButton)
        end)

    end

    -- ====================================================
    -- SWIPE LEFT or RIGHT = REPLY (Instagram-style slide animation)
    -- HOLD (0.6s) on NAME AREA ONLY = ENABLE PRIVATE CHAT
    -- Hold only ENABLES pvt — tap the [Name] tag left of the
    -- input box to DISABLE pvt (hold never disables pvt).
    -- Every message is swipeable (system, own, others).
    -- 50% sensitivity: threshold is 25px instead of 50px.
    -- ====================================================
    local holding = false
    local holdTriggered = false
    local swipeStartPos = nil
    local swipeTriggered = false
    local SWIPE_THRESHOLD = 25  -- 50% sensitivity (was 50px)

    -- ============================================================
    -- NAME HITBOX — transparent Frame overlaid on just the name
    -- portion of the message (top-left area). Hold logic ONLY fires
    -- here so holding the message body does NOT trigger private chat.
    -- ============================================================
    if not isSystem and senderUid ~= RealUserId then
        local nameHitboxY = (safeReply and safeReply ~= "") and 0 or 0
        local nameHitbox = Instance.new("Frame", TextButton)
        nameHitbox.Size = UDim2.new(0, 170, 0, 22)
        nameHitbox.Position = UDim2.new(0, 0, 0, nameHitboxY)
        nameHitbox.BackgroundTransparency = 1
        nameHitbox.BorderSizePixel = 0
        nameHitbox.ZIndex = 8
        nameHitbox.Active = true

        -- HOLD on NAME = enable PVT
        nameHitbox.InputBegan:Connect(function(inp)
            if inp.UserInputType ~= Enum.UserInputType.MouseButton1 and inp.UserInputType ~= Enum.UserInputType.Touch then return end
            holding = true
            holdTriggered = false
            task.delay(0.6, function()
                if holding and not swipeTriggered then
                    holdTriggered = true
                    -- ENABLE PVT ONLY (hold never disables pvt)
                    PrivateTargetId = senderUid
                    PrivateTargetName = safeName
                    Input.PlaceholderText = "[PVT] " .. safeName .. "..."
                    InputArea.BackgroundColor3 = Color3.fromRGB(40, 10, 50)
                    -- Show Roblox-chat-style [Name] tag left of input
                    PvtInputTag.Text = "[" .. safeName .. "]"
                    PvtInputTag.Visible = true
                    Input.Position = UDim2.new(0, 73, 0, 0)
                    Input.Size = UDim2.new(1, -117, 1, 0)
                end
            end)
        end)

        nameHitbox.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                local wasHolding = holding
                holding = false
                -- Quick tap (no hold triggered, no swipe) → open profile page
                if not holdTriggered and not swipeTriggered and wasHolding then
                    task.spawn(function()
                        showProfilePage(senderUid, safeName, safeName)
                    end)
                end
            end
        end)
    end

    -- SWIPE LEFT or RIGHT on any message bubble = REPLY
    -- ============================================================
    -- Every message is swipeable regardless of sender (system,
    -- own messages, others). UserInputService.InputChanged is used
    -- (global — fires anywhere on screen) so the swipe always
    -- registers even when the finger leaves the button bounds.
    -- Left swipe  → slides left  (-65px) then elastic snap back.
    -- Right swipe → slides right (+65px) then elastic snap back.
    -- ============================================================
    local swipeConn = nil
    local popupHoldFired = false  -- separate from nameHitbox holdTriggered
    -- Firebase key for this message (used by Edit / Unsend)
    local msgFbKey = (order and order ~= 0) and tostring(order) or nil
    local isOwnMsg = (senderUid == RealUserId)

    TextButton.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            swipeStartPos = inp.Position
            swipeTriggered = false
            popupHoldFired = false
            local tapPos = inp.Position

            -- ============================================================
            -- HOLD-POPUP TIMER (0.6 s) — fires context menu if no swipe
            -- and the nameHitbox pvt-hold (holdTriggered) didn't fire first
            -- ============================================================
            task.delay(0.6, function()
                if swipeTriggered or popupHoldFired then return end
                if not (inp.UserInputState == Enum.UserInputState.Begin
                     or inp.UserInputState == Enum.UserInputState.Change) then return end
                -- Don't show popup if nameHitbox already triggered pvt hold
                if holdTriggered then return end
                popupHoldFired = true
                closeMsgPopup()

                local opts = {}

                -- COPY TEXT — available for everyone
                table.insert(opts, {
                    icon = "📋", label = "Copy Text", destructive = false,
                    callback = function()
                        pcall(function()
                            if setclipboard then setclipboard(safeMsg)
                            elseif toclipboard then toclipboard(safeMsg) end
                        end)
                    end
                })

                -- PVT + REPLY — available when holding OTHERS' messages
                if not isOwnMsg and not isSystem then
                    -- VIEW PROFILE — open Instagram-style profile page
                    table.insert(opts, {
                        icon = "👤", label = "View Profile", destructive = false,
                        callback = function()
                            showProfilePage(senderUid, safeName, safeName)
                        end
                    })
                    -- PVT — start a private chat with this sender
                    table.insert(opts, {
                        icon = "💬", label = "PVT", destructive = false,
                        callback = function()
                            PrivateTargetId   = senderUid
                            PrivateTargetName = safeName
                            Input.PlaceholderText = "[PVT] " .. safeName .. "..."
                            InputArea.BackgroundColor3 = Color3.fromRGB(40, 10, 50)
                            PvtInputTag.Text    = "[" .. safeName .. "]"
                            PvtInputTag.Visible = true
                            Input.Position = UDim2.new(0, 73, 0, 0)
                            Input.Size     = UDim2.new(1, -117, 1, 0)
                        end
                    })
                    -- REPLY — quote this message in the input box
                    table.insert(opts, {
                        icon = "↩️", label = "Reply", destructive = false,
                        callback = function()
                            ReplyTargetName = safeName
                            local replyDisplayMsg = safeMsg:match("^%[STICKER:%d+%]$") and "🎭 Sticker" or safeMsg
                            ReplyTargetMsg  = replyDisplayMsg
                            ReplyBanner.Visible = true
                            ReplyLabel.Text = "Replying to " .. safeName .. ": " .. replyDisplayMsg
                            if isPrivate then
                                PrivateTargetId   = senderUid
                                PrivateTargetName = safeName
                                Input.PlaceholderText = "[PVT] " .. safeName .. "..."
                                InputArea.BackgroundColor3 = Color3.fromRGB(40, 10, 50)
                                PvtInputTag.Text    = "[" .. safeName .. "]"
                                PvtInputTag.Visible = true
                                Input.Position = UDim2.new(0, 73, 0, 0)
                                Input.Size     = UDim2.new(1, -117, 1, 0)
                            end
                        end
                    })
                end

                if isOwnMsg and not isSystem and msgFbKey then
                    -- EDIT — pre-fill input with this message text for in-place editing.
                    -- The next send() call will PATCH Firebase content and update the
                    -- existing bubble in-place — it does NOT post a new message.
                    table.insert(opts, {
                        icon = "✏️", label = "Edit", destructive = false,
                        callback = function()
                            editingKey = msgFbKey
                            -- Populate input with the raw (un-encoded) message text
                            Input.Text = msg
                            Input.ClearTextOnFocus = false  -- keep text when user taps
                            -- Tint input area blue to signal edit mode
                            InputArea.BackgroundColor3 = Color3.fromRGB(0, 40, 90)
                        end
                    })

                    -- UNSEND — delete from Firebase and remove UI
                    table.insert(opts, {
                        icon = "🗑️", label = "Unsend", destructive = true,
                        callback = function()
                            -- Remove from sorted key list
                            local newKeys = {}
                            for _, k in ipairs(activeMessageKeys) do
                                if k ~= msgFbKey then table.insert(newKeys, k) end
                            end
                            for i = #activeMessageKeys, 1, -1 do
                                activeMessageKeys[i] = nil
                            end
                            for _, k in ipairs(newKeys) do
                                table.insert(activeMessageKeys, k)
                            end
                            activeKeyToButton[msgFbKey] = nil
                            SpecialLabels[TextButton] = nil
                            -- Animate out and destroy wrapper
                            if wrapperFrame and wrapperFrame.Parent then
                                TweenService:Create(TextButton,
                                    TweenInfo.new(0.2, Enum.EasingStyle.Quad),
                                    {BackgroundTransparency = 1}):Play()
                                task.delay(0.22, function()
                                    if wrapperFrame and wrapperFrame.Parent then
                                        wrapperFrame:Destroy()
                                    end
                                end)
                            end
                            -- INSTANT unsend: write key to /unsent so ALL other clients
                            -- remove this message immediately (polled every 0.3s).
                            -- Also DELETE from /chat so new joiners never see it.
                            local req = syn and syn.request or http and http.request or request
                            if req then
                                task.spawn(function()
                                    pcall(function()
                                        -- 1. Publish to /unsent path — all live clients pick this up instantly
                                        req({
                                            Url    = UNSENT_URL .. "/" .. msgFbKey .. ".json",
                                            Method = "PUT",
                                            Body   = HttpService:JSONEncode(true)
                                        })
                                        -- 2. Hard-delete the message from /chat so new joiners never see it
                                        req({
                                            Url    = DATABASE_URL .. "/" .. msgFbKey .. ".json",
                                            Method = "DELETE"
                                        })
                                        -- 3. Clean up /unsent entry after 10 seconds (all clients will have seen it)
                                        task.delay(10, function()
                                            pcall(function()
                                                req({
                                                    Url    = UNSENT_URL .. "/" .. msgFbKey .. ".json",
                                                    Method = "DELETE"
                                                })
                                            end)
                                        end)
                                    end)
                                end)
                            end
                        end
                    })
                end

                showMsgPopup(Vector2.new(tapPos.X, tapPos.Y), opts)
            end)

            -- Start global swipe tracking connection
            if swipeConn then swipeConn:Disconnect() swipeConn = nil end
            swipeConn = UserInputService.InputChanged:Connect(function(uiInp)
                if not swipeStartPos then return end
                if uiInp.UserInputType ~= Enum.UserInputType.MouseMovement
                and uiInp.UserInputType ~= Enum.UserInputType.Touch then return end
                if holdTriggered or swipeTriggered then return end
                local dx = uiInp.Position.X - swipeStartPos.X
                local dy = math.abs(uiInp.Position.Y - swipeStartPos.Y)
                local absDx = math.abs(dx)
                -- Left or right swipe: enough horizontal movement, minimal vertical drift
                if absDx >= SWIPE_THRESHOLD and dy < 40 then
                    swipeTriggered = true
                    holding = false
                    if swipeConn then swipeConn:Disconnect() swipeConn = nil end
                    -- SLIDE ANIMATION: Instagram-style.
                    -- Right swipe → slide right (+65) then elastic snap back.
                    -- Left  swipe → slide left  (-65) then elastic snap back.
                    -- TextButton is inside wrapperFrame so UIListLayout does NOT
                    -- override its Position — TweenService moves it freely.
                    local slideOffset = (dx > 0) and 65 or -65
                    TweenService:Create(TextButton, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                        Position = UDim2.new(0, pfpOffset + slideOffset, 0, 0)
                    }):Play()
                    -- PFP slides alongside the bubble
                    local pfpImgRef = wrapperFrame:FindFirstChildWhichIsA("ImageButton") or wrapperFrame:FindFirstChildOfClass("ImageLabel")
                    if pfpImgRef then
                        TweenService:Create(pfpImgRef, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                            Position = UDim2.new(0, 2 + slideOffset, 0, 5)
                        }):Play()
                    end
                    task.delay(0.15, function()
                        if TextButton and TextButton.Parent then
                            TweenService:Create(TextButton, TweenInfo.new(0.45, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
                                Position = UDim2.new(0, pfpOffset, 0, 0)
                            }):Play()
                        end
                        if pfpImgRef and pfpImgRef.Parent then
                            TweenService:Create(pfpImgRef, TweenInfo.new(0.45, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
                                Position = UDim2.new(0, 2, 0, 5)
                            }):Play()
                        end
                    end)
                    -- TRIGGER REPLY
                    ReplyTargetName = safeName
                    local swipeReplyDisplayMsg = safeMsg:match("^%[STICKER:%d+%]$") and "🎭 Sticker" or safeMsg
                    ReplyTargetMsg  = swipeReplyDisplayMsg
                    ReplyBanner.Visible = true
                    ReplyLabel.Text = "Replying to " .. safeName .. ": " .. swipeReplyDisplayMsg
                    -- If the message was a private one
                    -- and sent by someone else, automatically route our reply privately
                    if isPrivate and senderUid ~= RealUserId then
                        PrivateTargetId   = senderUid
                        PrivateTargetName = safeName
                        Input.PlaceholderText = "[PVT] " .. safeName .. "..."
                        InputArea.BackgroundColor3 = Color3.fromRGB(255, 230, 245)
                        PvtInputTag.Text    = "[" .. safeName .. "]"
                        PvtInputTag.Visible = true
                        Input.Position = UDim2.new(0, 73, 0, 0)
                        Input.Size     = UDim2.new(1, -117, 1, 0)
                    end
                end
            end)
        end
    end)

    TextButton.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            holding = false
            swipeStartPos = nil
            if swipeConn then swipeConn:Disconnect() swipeConn = nil end
        end
    end)

    -- Smart auto-scroll: only scroll to bottom if the user hasn't manually scrolled up
    task.spawn(function()
        for i = 1, 3 do
            RunService.Heartbeat:Wait()
        end
        if ChatLog and not _userScrolledUp then
            ChatLog.CanvasPosition = Vector2.new(0, 99999999)
        end
    end)
end

-- ============================================================
-- DATABASE HELPERS
-- ============================================================
local function cleanDatabase()
    local req = syn and syn.request or http and http.request or request
    if req then req({Url = DATABASE_URL .. ".json", Method = "DELETE"}) end
end

local function broadcastCommand(targetId, cmdName, val)
    local timestamp = string.format("%012d", os.time()) .. math.random(100, 999)
    local data = {["Sender"] = "SYSTEM_CMD", ["TargetId"] = targetId, ["Cmd"] = cmdName, ["Val"] = val, ["Server"] = JobId}
    local req = syn and syn.request or http and http.request or request
    if req then
        req({Url = DATABASE_URL .. "/" .. timestamp .. ".json", Method = "PUT", Body = HttpService:JSONEncode(data)})
    end
end

-- ============================================================
-- LOCAL COMMANDS (available to ALL users)
-- ============================================================
local function handleLocalCommands(msg)
    local args = string.split(msg, " ")
    local cmd = string.lower(args[1])

    -- /clear — wipe local UI only
    if cmd == "/clear" then
        for _, child in pairs(ChatLog:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end  -- wrapperFrames
        sortedMessageKeys = {}
        keyToButton = {}
        addMessage("SYSTEM", "Chat cleared locally.", true, 0, 0, false, true)
        return true

    -- /fly — toggle fly (stable for both PC and mobile)
    elseif cmd == "/fly" then
        Flying = not Flying
        if Flying then
            local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
            local hrp = char:WaitForChild("HumanoidRootPart")
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            -- Remove any leftover fly constraints from a previous session
            local oldBV = hrp:FindFirstChild("AresFlyBV")
            local oldBG = hrp:FindFirstChild("AresFlyBG")
            if oldBV then oldBV:Destroy() end
            if oldBG then oldBG:Destroy() end
            if humanoid then humanoid.PlatformStand = true end
            local bv = Instance.new("BodyVelocity", hrp)
            bv.Name     = "AresFlyBV"
            bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
            bv.Velocity = Vector3.new(0, 0, 0)
            local bg = Instance.new("BodyGyro", hrp)
            bg.Name      = "AresFlyBG"
            bg.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
            bg.P         = 2e5
            bg.D         = 1e3
            bg.CFrame    = hrp.CFrame
            task.spawn(function()
                while Flying and hrp and hrp.Parent do
                    RunService.Heartbeat:Wait()
                    local speed = 50
                    local cam   = workspace.CurrentCamera
                    -- ── Horizontal movement ─────────────────────────────────
                    -- humanoid.MoveDirection is in WORLD space and is already
                    -- camera-adjusted by Roblox for both PC (WASD) and mobile
                    -- (thumbstick). Use it directly — do NOT project through
                    -- camera vectors again (that double-rotates the direction).
                    local md = humanoid and humanoid.MoveDirection or Vector3.new(0,0,0)
                    local flatMove = Vector3.new(md.X, 0, md.Z)
                    local moveDir
                    if flatMove.Magnitude > 0.01 then
                        moveDir = flatMove.Unit * speed
                    else
                        moveDir = Vector3.new(0, 0, 0)
                    end
                    -- ── Vertical movement (PC: Space/Shift/E/Q) ─────────────
                    local goUp   = UserInputService:IsKeyDown(Enum.KeyCode.Space)
                                or UserInputService:IsKeyDown(Enum.KeyCode.E)
                    local goDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
                                or UserInputService:IsKeyDown(Enum.KeyCode.Q)
                    if goUp   then moveDir = Vector3.new(moveDir.X,  speed, moveDir.Z) end
                    if goDown then moveDir = Vector3.new(moveDir.X, -speed, moveDir.Z) end
                    bv.Velocity = moveDir
                    -- ── Gyro: face movement direction; idle → face camera ────
                    local horizDir = Vector3.new(moveDir.X, 0, moveDir.Z)
                    if horizDir.Magnitude > 0.1 then
                        bg.CFrame = CFrame.lookAt(Vector3.new(0,0,0), horizDir)
                    else
                        -- When hovering still, keep character facing camera direction
                        local camFlat = Vector3.new(
                            cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
                        if camFlat.Magnitude > 0.01 then
                            bg.CFrame = CFrame.lookAt(Vector3.new(0,0,0), camFlat)
                        end
                    end
                end
                -- Cleanup when fly is toggled off or character removed
                if bv and bv.Parent then bv:Destroy() end
                if bg and bg.Parent then bg:Destroy() end
                if humanoid and humanoid.Parent then humanoid.PlatformStand = false end
            end)
        else
            -- Disable fly: remove constraints and restore walking
            local char = LocalPlayer.Character
            if char then
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local bv = hrp:FindFirstChild("AresFlyBV")
                    local bg = hrp:FindFirstChild("AresFlyBG")
                    if bv then bv:Destroy() end
                    if bg then bg:Destroy() end
                end
                local humanoid = char:FindFirstChildOfClass("Humanoid")
                if humanoid then humanoid.PlatformStand = false end
            end
        end
        addMessage("SYSTEM", "Fly " .. (Flying and "enabled." or "disabled."), true, 0, 0, false, true)
        return true

    -- /noclip — toggle noclip
    elseif cmd == "/noclip" then
        Noclip = not Noclip
        task.spawn(function()
            while Noclip do
                RunService.Stepped:Wait()
                if LocalPlayer.Character then
                    for _, p in pairs(LocalPlayer.Character:GetDescendants()) do
                        if p:IsA("BasePart") then p.CanCollide = false end
                    end
                end
            end
        end)
        addMessage("SYSTEM", "Noclip " .. (Noclip and "enabled." or "disabled."), true, 0, 0, false, true)
        return true

    -- /nosit — disable sitting
    elseif cmd == "/nosit" then
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.Sit = false
            LocalPlayer.Character.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
        end
        addMessage("SYSTEM", "Sit disabled.", true, 0, 0, false, true)
        return true

    -- /sit — force sit
    elseif cmd == "/sit" then
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.Sit = true
        end
        addMessage("SYSTEM", "Sitting.", true, 0, 0, false, true)
        return true

    -- /speed [val] — set own walkspeed (no target = self)
    elseif cmd == "/speed" and args[2] and not args[3] then
        local val = tonumber(args[2])
        if val and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.WalkSpeed = val
            addMessage("SYSTEM", "WalkSpeed set to " .. val .. ".", true, 0, 0, false, true)
        end
        return true

    -- /jump [val] — set own jump power (no target = self)
    elseif cmd == "/jump" and args[2] and not args[3] then
        local val = tonumber(args[2])
        if val and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.JumpPower = val
            addMessage("SYSTEM", "JumpPower set to " .. val .. ".", true, 0, 0, false, true)
        end
        return true

    -- /invisible — toggle own invisibility
    elseif cmd == "/invisible" and not args[2] then
        IsInvisible = not IsInvisible
        if LocalPlayer.Character then
            for _, part in pairs(LocalPlayer.Character:GetDescendants()) do
                if part:IsA("BasePart") or part:IsA("Decal") then
                    part.Transparency = IsInvisible and 1 or 0
                end
            end
        end
        addMessage("SYSTEM", "Invisibility " .. (IsInvisible and "enabled." or "disabled."), true, 0, 0, false, true)
        return true

    -- /me [text] — roleplay action sent to chat
    elseif cmd == "/me" then
        local rest = table.concat(args, " ", 2)
        if rest ~= "" then
            return false -- let send() handle it as a special /me message
        end
        return true

    -- /time — show current time
    elseif cmd == "/time" then
        local h = tonumber(os.date("%H"))
        local m = os.date("%M")
        local ampm = h >= 12 and "PM" or "AM"
        h = h % 12
        if h == 0 then h = 12 end
        addMessage("SYSTEM", "Current time: " .. h .. ":" .. m .. " " .. ampm, true, 0, 0, false, true)
        return true

    -- /name [text] — set RP name in Brookhaven (or just local display alias)
    elseif cmd == "/name" and args[2] then
        local newName = table.concat(args, " ", 2)
        if game.PlaceId == 4924922222 then
            local rs = game:GetService("ReplicatedStorage")
            local rpRemote = rs:FindFirstChild("RE")
            if rpRemote then
                local nameRemote = rpRemote:FindFirstChild("1RPNam1eTex1t")
                if nameRemote then
                    pcall(function() nameRemote:FireServer("RolePlayName", newName) end)
                    addMessage("SYSTEM", "RP name set to: " .. newName, true, 0, 0, false, true)
                end
            end
        else
            addMessage("SYSTEM", "Name command only works in Brookhaven.", true, 0, 0, false, true)
        end
        return true

    -- ============================================================
    -- /mute [name] — LOCAL MUTE (only visible to this player)
    -- Suppresses messages from the target in the local chat GUI only.
    -- Does NOT affect other players or Firebase.
    -- ============================================================
    elseif cmd == "/mute" and args[2] then
        local targetName = table.concat(args, " ", 2)
        local target = GetPlayerByName(targetName)
        if target then
            if target.UserId == RealUserId then
                addMessage("SYSTEM", "You cannot mute yourself.", true, 0, 0, false, true)
            elseif target.UserId == CREATOR_ID then
                addMessage("SYSTEM", "You cannot mute the Creator.", true, 0, 0, false, true)
            else
                MutedPlayers[target.UserId] = true
                addMessage("SYSTEM", "Locally muted " .. target.DisplayName .. ". Only you see this.", true, 0, 0, false, true)
            end
        else
            addMessage("SYSTEM", "Player '" .. targetName .. "' not found.", true, 0, 0, false, true)
        end
        return true

    -- /unmute [name] — LOCAL UNMUTE
    elseif cmd == "/unmute" and args[2] then
        local targetName = table.concat(args, " ", 2)
        local target = GetPlayerByName(targetName)
        if target then
            MutedPlayers[target.UserId] = nil
            addMessage("SYSTEM", "Locally unmuted " .. target.DisplayName .. ".", true, 0, 0, false, true)
        else
            addMessage("SYSTEM", "Player '" .. targetName .. "' not found.", true, 0, 0, false, true)
        end
        return true

    -- ============================================================
    -- EXTRA USER COMMANDS (50+)
    -- ============================================================

    -- /view [name] — view / spectate a player (shifts camera to their character)
    elseif cmd == "/view" and args[2] then
        local target = GetPlayerByName(args[2])
        if target and target.Character then
            workspace.CurrentCamera.CameraSubject = target.Character:FindFirstChildOfClass("Humanoid") or target.Character:FindFirstChild("HumanoidRootPart")
            addMessage("SYSTEM", "Viewing " .. target.DisplayName .. ".", true, 0, 0, false, true)
        else
            addMessage("SYSTEM", "Player not found.", true, 0, 0, false, true)
        end
        return true

    -- /unview — restore camera to own character
    elseif cmd == "/unview" then
        if LocalPlayer.Character then
            workspace.CurrentCamera.CameraSubject = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            addMessage("SYSTEM", "Camera restored.", true, 0, 0, false, true)
        end
        return true

    -- /to [name] — teleport self to player
    elseif cmd == "/to" and args[2] then
        local target = GetPlayerByName(args[2])
        if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                LocalPlayer.Character.HumanoidRootPart.CFrame = target.Character.HumanoidRootPart.CFrame * CFrame.new(4, 0, 0)
                addMessage("SYSTEM", "Teleported to " .. target.DisplayName .. ".", true, 0, 0, false, true)
            end
        else
            addMessage("SYSTEM", "Player not found.", true, 0, 0, false, true)
        end
        return true

    -- /goto [name] — alias for /to
    elseif cmd == "/goto" and args[2] then
        local target = GetPlayerByName(args[2])
        if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                LocalPlayer.Character.HumanoidRootPart.CFrame = target.Character.HumanoidRootPart.CFrame * CFrame.new(4, 0, 0)
                addMessage("SYSTEM", "Teleported to " .. target.DisplayName .. ".", true, 0, 0, false, true)
            end
        else
            addMessage("SYSTEM", "Player not found.", true, 0, 0, false, true)
        end
        return true

    -- /bring [name] — bring player to self (local only)
    elseif cmd == "/bring" and args[2] then
        local target = GetPlayerByName(args[2])
        if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                target.Character.HumanoidRootPart.CFrame = LocalPlayer.Character.HumanoidRootPart.CFrame * CFrame.new(4, 0, 0)
                addMessage("SYSTEM", "Brought " .. target.DisplayName .. " to you (local).", true, 0, 0, false, true)
            end
        else
            addMessage("SYSTEM", "Player not found.", true, 0, 0, false, true)
        end
        return true

    -- /ws [val] — set walkspeed (alias)
    elseif cmd == "/ws" and args[2] then
        local val = tonumber(args[2])
        if val and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.WalkSpeed = val
            addMessage("SYSTEM", "WalkSpeed set to " .. val .. ".", true, 0, 0, false, true)
        end
        return true

    -- /jp [val] — set jump power (alias)
    elseif cmd == "/jp" and args[2] then
        local val = tonumber(args[2])
        if val and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.JumpPower = val
            addMessage("SYSTEM", "JumpPower set to " .. val .. ".", true, 0, 0, false, true)
        end
        return true

    -- /gravity [val] — set workspace gravity
    elseif cmd == "/gravity" and args[2] then
        local val = tonumber(args[2])
        if val then
            workspace.Gravity = val
            addMessage("SYSTEM", "Gravity set to " .. val .. ".", true, 0, 0, false, true)
        end
        return true

    -- /fog [val] — set fog end distance
    elseif cmd == "/fog" and args[2] then
        local val = tonumber(args[2])
        if val then
            local lighting = game:GetService("Lighting")
            lighting.FogEnd = val
            addMessage("SYSTEM", "Fog end set to " .. val .. ".", true, 0, 0, false, true)
        end
        return true

    -- /day — set daytime
    elseif cmd == "/day" then
        game:GetService("Lighting").ClockTime = 14
        addMessage("SYSTEM", "Time set to day.", true, 0, 0, false, true)
        return true

    -- /night — set night time
    elseif cmd == "/night" then
        game:GetService("Lighting").ClockTime = 0
        addMessage("SYSTEM", "Time set to night.", true, 0, 0, false, true)
        return true

    -- /reset — reset own character
    elseif cmd == "/reset" then
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.Health = 0
            addMessage("SYSTEM", "Resetting character...", true, 0, 0, false, true)
        end
        return true

    -- /respawn — reload character
    elseif cmd == "/respawn" then
        LocalPlayer:LoadCharacter()
        addMessage("SYSTEM", "Respawning...", true, 0, 0, false, true)
        return true

    -- /heal — restore own health to max
    elseif cmd == "/heal" then
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            local hum = LocalPlayer.Character.Humanoid
            hum.Health = hum.MaxHealth
            addMessage("SYSTEM", "Health restored.", true, 0, 0, false, true)
        end
        return true

    -- /god — set own health to very high
    elseif cmd == "/god" then
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.MaxHealth = math.huge
            LocalPlayer.Character.Humanoid.Health    = math.huge
            addMessage("SYSTEM", "God mode ON.", true, 0, 0, false, true)
        end
        return true

    -- /ungod — restore normal health cap
    elseif cmd == "/ungod" then
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.MaxHealth = 100
            LocalPlayer.Character.Humanoid.Health    = 100
            addMessage("SYSTEM", "God mode OFF.", true, 0, 0, false, true)
        end
        return true

    -- /ping — show latency
    elseif cmd == "/ping" then
        local stats = game:GetService("Stats")
        local ping = stats.Network.ServerStatsItem["Data Ping"]:GetValue()
        addMessage("SYSTEM", "Ping: " .. math.floor(ping) .. " ms", true, 0, 0, false, true)
        return true

    -- /players — list all players in server
    elseif cmd == "/players" then
        addMessage("SYSTEM", "Players in server:", true, 0, 0, false, true)
        for _, p in pairs(Players:GetPlayers()) do
            addMessage("SYSTEM", "  • " .. p.DisplayName .. " (@" .. p.Name .. ")", true, 0, 0, false, true)
        end
        return true

    -- /server — show server/job id
    elseif cmd == "/server" then
        addMessage("SYSTEM", "Server ID: " .. tostring(JobId), true, 0, 0, false, true)
        return true

    -- /gameid — show game ID
    elseif cmd == "/gameid" then
        addMessage("SYSTEM", "Game ID: " .. tostring(game.GameId), true, 0, 0, false, true)
        return true

    -- /placeid — show place ID
    elseif cmd == "/placeid" then
        addMessage("SYSTEM", "Place ID: " .. tostring(game.PlaceId), true, 0, 0, false, true)
        return true

    -- /fps — show current FPS
    elseif cmd == "/fps" then
        local fps = math.floor(1/RunService.Heartbeat:Wait())
        addMessage("SYSTEM", "FPS: ~" .. fps, true, 0, 0, false, true)
        return true

    -- /zoom [val] — set camera zoom distance
    elseif cmd == "/zoom" and args[2] then
        local val = tonumber(args[2])
        if val then
            LocalPlayer.CameraMaxZoomDistance = val
            LocalPlayer.CameraMinZoomDistance = math.min(val, LocalPlayer.CameraMinZoomDistance)
            addMessage("SYSTEM", "Camera zoom set to " .. val .. ".", true, 0, 0, false, true)
        end
        return true

    -- /fov [val] — set field of view
    elseif cmd == "/fov" and args[2] then
        local val = tonumber(args[2])
        if val then
            workspace.CurrentCamera.FieldOfView = val
            addMessage("SYSTEM", "FOV set to " .. val .. ".", true, 0, 0, false, true)
        end
        return true

    -- /spin — make character spin
    elseif cmd == "/spin" then
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            local hrp = char.HumanoidRootPart
            local old = hrp:FindFirstChild("AresSpinBG")
            if old then old:Destroy() end
            local bg = Instance.new("BodyAngularVelocity", hrp)
            bg.Name = "AresSpinBG"
            bg.AngularVelocity = Vector3.new(0, 20, 0)
            bg.MaxTorque = Vector3.new(0, 1e9, 0)
            bg.P = 1e5
            addMessage("SYSTEM", "Spinning! /unspin to stop.", true, 0, 0, false, true)
        end
        return true

    -- /unspin — stop spinning
    elseif cmd == "/unspin" then
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            local bg = char.HumanoidRootPart:FindFirstChild("AresSpinBG")
            if bg then bg:Destroy() end
            addMessage("SYSTEM", "Spin stopped.", true, 0, 0, false, true)
        end
        return true

    -- /lock — anchor own HRP (freeze self)
    elseif cmd == "/lock" then
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            LocalPlayer.Character.HumanoidRootPart.Anchored = true
            addMessage("SYSTEM", "Self locked (frozen).", true, 0, 0, false, true)
        end
        return true

    -- /unlock — unanchor own HRP
    elseif cmd == "/unlock" then
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            LocalPlayer.Character.HumanoidRootPart.Anchored = false
            addMessage("SYSTEM", "Self unlocked.", true, 0, 0, false, true)
        end
        return true

    -- /hitbox [val] — resize own HRP hitbox
    elseif cmd == "/hitbox" and args[2] then
        local val = tonumber(args[2])
        if val and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            LocalPlayer.Character.HumanoidRootPart.Size = Vector3.new(val, val, val)
            addMessage("SYSTEM", "Hitbox size set to " .. val .. ".", true, 0, 0, false, true)
        end
        return true

    -- /tools — give all tools from StarterPack
    elseif cmd == "/tools" then
        pcall(function()
            local sp = game:GetService("StarterPack")
            local bp = LocalPlayer.Backpack
            for _, tool in pairs(sp:GetChildren()) do
                if tool:IsA("Tool") and not bp:FindFirstChild(tool.Name) then
                    tool:Clone().Parent = bp
                end
            end
        end)
        addMessage("SYSTEM", "Tools added from StarterPack.", true, 0, 0, false, true)
        return true

    -- /notools — remove all tools from backpack
    elseif cmd == "/notools" then
        if LocalPlayer.Backpack then
            for _, t in pairs(LocalPlayer.Backpack:GetChildren()) do t:Destroy() end
        end
        if LocalPlayer.Character then
            for _, t in pairs(LocalPlayer.Character:GetChildren()) do if t:IsA("Tool") then t:Destroy() end end
        end
        addMessage("SYSTEM", "All tools removed.", true, 0, 0, false, true)
        return true

    -- /shout [text] — post a shout-style message in chat
    elseif cmd == "/shout" and args[2] then
        local text = table.concat(args, " ", 2)
        return false  -- route to send() as a normal message prefixed with SHOUT

    -- /afk — toggle AFK status
    elseif cmd == "/afk" then
        addMessage("SYSTEM", "AFK mode toggled. Others will see your AFK tag.", true, 0, 0, false, true)
        return true

    -- /info [name] — show info about a player
    elseif cmd == "/info" and args[2] then
        local target = GetPlayerByName(args[2])
        if target then
            addMessage("SYSTEM", "=== Info: " .. target.DisplayName .. " ===", true, 0, 0, false, true)
            addMessage("SYSTEM", "Username: @" .. target.Name, true, 0, 0, false, true)
            addMessage("SYSTEM", "UserID: " .. tostring(target.UserId), true, 0, 0, false, true)
            addMessage("SYSTEM", "Account Age: " .. tostring(target.AccountAge) .. " days", true, 0, 0, false, true)
            addMessage("SYSTEM", "Team: " .. (target.Team and target.Team.Name or "None"), true, 0, 0, false, true)
        else
            addMessage("SYSTEM", "Player not found.", true, 0, 0, false, true)
        end
        return true

    -- /age [name] — show account age
    elseif cmd == "/age" and args[2] then
        local target = GetPlayerByName(args[2])
        if target then
            addMessage("SYSTEM", target.DisplayName .. " account age: " .. tostring(target.AccountAge) .. " days", true, 0, 0, false, true)
        else
            addMessage("SYSTEM", "Player not found.", true, 0, 0, false, true)
        end
        return true

    -- /online — show how many players are in server
    elseif cmd == "/online" then
        local count = #Players:GetPlayers()
        addMessage("SYSTEM", "Players online: " .. count .. "/" .. Players.MaxPlayers, true, 0, 0, false, true)
        return true

    -- /dms — toggle private mode reminder
    elseif cmd == "/dms" then
        addMessage("SYSTEM", "Hold a message and tap PVT to start a private chat.", true, 0, 0, false, true)
        return true

    -- /ambient [r] [g] [b] — set ambient light color
    elseif cmd == "/ambient" and args[2] and args[3] and args[4] then
        local r, g, b = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
        if r and g and b then
            game:GetService("Lighting").Ambient = Color3.fromRGB(r, g, b)
            addMessage("SYSTEM", "Ambient set to " .. r .. "," .. g .. "," .. b .. ".", true, 0, 0, false, true)
        end
        return true

    -- /dance — play idle animation (sit toggle trick)
    elseif cmd == "/dance" then
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid") then
            local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            pcall(function()
                local animTrack = hum:LoadAnimation(Instance.new("Animation"))
                animTrack:Play()
            end)
        end
        addMessage("SYSTEM", "Dance command sent! (Game must support animations)", true, 0, 0, false, true)
        return true

    -- /sit2 — force sit from script side
    elseif cmd == "/sit2" then
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid") then
            LocalPlayer.Character:FindFirstChildOfClass("Humanoid").Sit = true
            addMessage("SYSTEM", "Force sitting.", true, 0, 0, false, true)
        end
        return true

    -- /lag — show network stats
    elseif cmd == "/lag" then
        local stats = game:GetService("Stats")
        local ping = 0
        pcall(function() ping = stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
        addMessage("SYSTEM", "Network ping: ~" .. math.floor(ping) .. "ms", true, 0, 0, false, true)
        return true

    -- /back — teleport back to spawn
    elseif cmd == "/back" then
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(0, 5, 0)
            addMessage("SYSTEM", "Teleported to origin.", true, 0, 0, false, true)
        end
        return true

    -- /pm [name] [msg] — send private message via chat
    elseif cmd == "/pm" and args[2] and args[3] then
        local target = GetPlayerByName(args[2])
        if target then
            PrivateTargetId   = target.UserId
            PrivateTargetName = target.DisplayName
            Input.PlaceholderText = "[PVT] " .. target.DisplayName .. "..."
            InputArea.BackgroundColor3 = Color3.fromRGB(40, 10, 50)
            PvtInputTag.Text    = "[" .. target.DisplayName .. "]"
            PvtInputTag.Visible = true
            Input.Position = UDim2.new(0, 73, 0, 0)
            Input.Size     = UDim2.new(1, -117, 1, 0)
            addMessage("SYSTEM", "PM mode to " .. target.DisplayName .. " activated.", true, 0, 0, false, true)
        else
            addMessage("SYSTEM", "Player not found.", true, 0, 0, false, true)
        end
        return true

    -- /emote [name] — print emote hint
    elseif cmd == "/emote" and args[2] then
        local emoteName = args[2]
        addMessage("SYSTEM", "Emote '" .. emoteName .. "' — use /e " .. emoteName .. " in Roblox chat for in-game emotes.", true, 0, 0, false, true)
        return true

    -- /nametag [text] — set local display name above character
    elseif cmd == "/nametag" and args[2] then
        local tagText = table.concat(args, " ", 2)
        if LocalPlayer.Character then
            for _, d in pairs(LocalPlayer.Character:GetDescendants()) do
                if d:IsA("BillboardGui") and d.Name == "AresNameTag" then d:Destroy() end
            end
            local hrp = LocalPlayer.Character:FindFirstChild("HumanoidRootPart") or LocalPlayer.Character:FindFirstChild("Head")
            if hrp then
                local bb = Instance.new("BillboardGui", hrp)
                bb.Name = "AresNameTag"
                bb.Size = UDim2.new(0, 100, 0, 26)
                bb.StudsOffset = Vector3.new(0, 3, 0)
                bb.AlwaysOnTop = false
                local lbl = Instance.new("TextLabel", bb)
                lbl.Size = UDim2.new(1,0,1,0)
                lbl.BackgroundTransparency = 1
                lbl.Text = tagText
                lbl.TextColor3 = Color3.fromRGB(220, 180, 255)
                lbl.Font = Enum.Font.GothamBold
                lbl.TextSize = 14
                addMessage("SYSTEM", "Nametag set to: " .. tagText, true, 0, 0, false, true)
            end
        end
        return true

    -- /hat — un-hide accessories
    elseif cmd == "/hat" then
        if LocalPlayer.Character then
            for _, acc in pairs(LocalPlayer.Character:GetChildren()) do
                if acc:IsA("Accessory") then
                    local h = acc:FindFirstChild("Handle")
                    if h then h.Transparency = 0 end
                end
            end
            addMessage("SYSTEM", "Accessories shown.", true, 0, 0, false, true)
        end
        return true

    -- /nohat — hide accessories
    elseif cmd == "/nohat" then
        if LocalPlayer.Character then
            for _, acc in pairs(LocalPlayer.Character:GetChildren()) do
                if acc:IsA("Accessory") then
                    local h = acc:FindFirstChild("Handle")
                    if h then h.Transparency = 1 end
                end
            end
            addMessage("SYSTEM", "Accessories hidden.", true, 0, 0, false, true)
        end
        return true

    -- ============================================================
    -- /stopgame — GAMEBOT HOST ONLY — stops the running game immediately
    elseif cmd == "/stopgame" then
        if not gameBotActive and not gameBotPending then
            addMessage("SYSTEM", "🎮 No game is currently running.", true, 0, 0, false, true)
        elseif not gameBotIsHost then
            addMessage("SYSTEM", "🎮 Only the game host can stop the game.", true, 0, 0, false, true)
        else
            gameBotActive   = false
            gameBotIsHost   = false
            gameBotPending  = false
            gameBotAnswer   = nil
            gameBotWinCounts = {}
            gameBotWinnerUids = {}
            gameBotSendSystem("🛑 AresBot — The host has stopped the game.")
            addMessage("SYSTEM", "🛑 Game stopped.", true, 0, 0, false, true)
        end
        return true

    -- ============================================================
    -- /gamebot — start AresBot game session with game selection menu
    elseif cmd == "/gamebot" then
        if gameBotActive then
            addMessage("SYSTEM", "🎮 A game is already running! Wait for it to finish or type /stopgame to stop it.", true, 0, 0, false, true)
            return true
        end
        if gameBotPending then
            addMessage("SYSTEM", "🎮 Choose a game! Type 1, 2, 3 or 4.", true, 0, 0, false, true)
            return true
        end
        gameBotPending = true
        addMessage("SYSTEM", "🎮 AresBot: Choose a game! (type the number)", true, 0, 0, false, true)
        addMessage("SYSTEM", "1️⃣  Fast Math — quick arithmetic (medium)", true, 0, 0, false, true)
        addMessage("SYSTEM", "2️⃣  Unscramble — unscramble a Roblox word", true, 0, 0, false, true)
        addMessage("SYSTEM", "3️⃣  Guess the Number — pick 1-50 (with hint)", true, 0, 0, false, true)
        addMessage("SYSTEM", "4️⃣  Fill the Blank — complete the Roblox word (e.g. RO_LOX)", true, 0, 0, false, true)
        addMessage("SYSTEM", "🏆 10 rounds — player with most round wins earns 1 real permanent trophy!", true, 0, 0, false, true)
        addMessage("SYSTEM", "🛑 Type /stopgame to stop the game early (host only).", true, 0, 0, false, true)
        return true

    -- ============================================================
    -- /commands — show ALL user commands as local system messages
    -- ============================================================
    elseif cmd == "/commands" then
        local commandList = {
            "=== MOVEMENT ===",
            "/fly — Toggle fly",
            "/noclip — Toggle noclip",
            "/sit — Force sit",
            "/sit2 — Force sit (script-side)",
            "/nosit — Disable sit",
            "/spin — Start spinning",
            "/unspin — Stop spinning",
            "/lock — Freeze self (anchored)",
            "/unlock — Unfreeze self",
            "/dance — Play dance emote",
            "",
            "=== TELEPORT ===",
            "/to [name] — Teleport to player",
            "/goto [name] — Teleport to player (alias)",
            "/bring [name] — Bring player to you (local)",
            "/back — Teleport to origin (0,0,0)",
            "",
            "=== STATS ===",
            "/speed [val] — Set WalkSpeed",
            "/ws [val] — Set WalkSpeed (alias)",
            "/jump [val] — Set JumpPower",
            "/jp [val] — Set JumpPower (alias)",
            "/gravity [val] — Set gravity",
            "/zoom [val] — Set camera zoom",
            "/fov [val] — Set field of view",
            "",
            "=== HEALTH ===",
            "/heal — Restore max health",
            "/god — God mode (infinite health)",
            "/ungod — Disable god mode",
            "",
            "=== WORLD ===",
            "/fog [val] — Set fog end distance",
            "/day — Set daytime",
            "/night — Set nighttime",
            "/ambient [r] [g] [b] — Set ambient color",
            "",
            "=== CAMERA ===",
            "/view [name] — Spectate a player",
            "/unview — Restore camera",
            "",
            "=== PLAYER INFO ===",
            "/players — List all players",
            "/info [name] — Player info",
            "/age [name] — Account age",
            "/online — Players online count",
            "/ping — Show ping",
            "/fps — Show FPS",
            "/lag — Network stats",
            "/server — Server ID",
            "/gameid — Game ID",
            "/placeid — Place ID",
            "",
            "=== APPEARANCE ===",
            "/invisible — Toggle own invisibility",
            "/hat — Show accessories",
            "/nohat — Hide accessories",
            "/nametag [text] — Set local nametag",
            "/hitbox [val] — Resize HRP hitbox",
            "",
            "=== TOOLS ===",
            "/tools — Get StarterPack tools",
            "/notools — Remove all tools",
            "",
            "=== CHAT ===",
            "/me [text] — Roleplay action message",
            "/pm [name] [msg] — Private message",
            "/dms — Private chat reminder",
            "/afk — AFK reminder",
            "/emote [name] — Emote hint",
            "/gamebot — Start AresBot game (Math/Unscramble/Guess/Fill)",
            "/stopgame — Stop running gamebot (host only)",
            "",
            "=== MISC ===",
            "/time — Show current time",
            "/name [text] — RP name (Brookhaven)",
            "/mute [name] — Locally mute player",
            "/unmute [name] — Locally unmute player",
            "/clear — Clear local chat",
            "/reset — Reset character",
            "/respawn — Reload character",
            "/commands — Show this list",
        }
        addMessage("SYSTEM", "╔══ ARES RECHAT COMMANDS ══╗", true, 0, 0, false, true)
        for _, line in ipairs(commandList) do
            addMessage("SYSTEM", line, true, 0, 0, false, true)
        end
        addMessage("SYSTEM", "╚══ END OF COMMANDS ══╝", true, 0, 0, false, true)
        return true

    end

    return false
end

-- ============================================================
-- SEND MESSAGE (with Reply support + /me handling)
-- ============================================================
send = function(msg, isSystem, isAutoClean)
    if msg == "" then return end

    -- KICKED/BANNED GUARD: block any send attempt after kick/ban
    if isKickedOrBanned then return end

    -- ============================================================
    -- EDIT MODE — when editingKey is set, patch the existing
    -- Firebase message in-place instead of posting a new one.
    -- Restores the input area colour and ClearTextOnFocus flag.
    -- ============================================================
    if editingKey and not isSystem then
        local ekCopy  = editingKey
        editingKey    = nil
        Input.ClearTextOnFocus = true
        InputArea.BackgroundColor3 = Color3.fromRGB(20, 10, 45)

        -- Update the bubble text locally so the change is instant
        local btn = keyToButton[ekCopy]
        if btn then
            local safeNewMsg = SafeEncodeMsg(msg)
            if SpecialLabels[btn] then
                -- RGB-loop messages: update the cached msg field
                SpecialLabels[btn].msg = safeNewMsg
            elseif NormalTitleLabels[btn] then
                -- Follower-title messages: update the cached msg field
                NormalTitleLabels[btn].msg = safeNewMsg
            else
                -- Plain messages: rewrite text preserving the name prefix
                local cur = btn.Text or ""
                local colonPos = string.find(cur, ": ", 1, true)
                if colonPos then
                    btn.Text = string.sub(cur, 1, colonPos + 1) .. safeNewMsg
                end
            end
        end

        -- PATCH only the Content field in Firebase (all other fields untouched)
        task.spawn(function()
            pcall(function()
                local req2 = syn and syn.request or http and http.request or request
                if req2 then
                    req2({
                        Url    = DATABASE_URL .. "/" .. ekCopy .. ".json",
                        Method = "PATCH",
                        Body   = HttpService:JSONEncode({Content = msg})
                    })
                end
            end)
        end)
        return
    end

    -- 200 CHARACTER LIMIT ENFORCEMENT
    if #msg > MAX_CHAR_LIMIT then
        addMessage("SYSTEM", "Message too long! Max " .. MAX_CHAR_LIMIT .. " characters.", true, 0, 0, false, true)
        return
    end

    -- ANTI-SPAM CHECK (skip for system messages and admin commands)
    if not isSystem and string.sub(msg, 1, 1) ~= "/" then
        local now = os.time()
        -- Reset rolling window
        if now - _spamWindowStart >= SPAM_WINDOW then
            _spamCount = 0
            _spamWindowStart = now
        end
        -- Minimum interval between messages
        if now - _lastSentTime < SPAM_INTERVAL then
            addMessage("SYSTEM", "⛔ Slow down! You are sending messages too fast.", true, 0, 0, false, true)
            return
        end
        -- Same message repeated
        if msg == _lastSentMsg then
            addMessage("SYSTEM", "⛔ Don't repeat the same message.", true, 0, 0, false, true)
            return
        end
        -- Too many messages in window
        _spamCount = _spamCount + 1
        if _spamCount > SPAM_MAX then
            addMessage("SYSTEM", "⛔ Anti-spam: You've sent too many messages. Please wait.", true, 0, 0, false, true)
            _spamCount = SPAM_MAX  -- keep capped so it recovers on next window
            return
        end
        _lastSentTime = now
        _lastSentMsg  = msg
    end

    -- /me handling: convert to emote-style message before local command check
    local args = string.split(msg, " ")
    if string.lower(args[1]) == "/me" then
        local rest = table.concat(args, " ", 2)
        if rest ~= "" then
            local emoteMsg = "* " .. RealDisplayName .. " " .. rest .. " *"
            local timestamp = string.format("%012d", os.time()) .. math.random(100, 999)
            local data = {
                ["Sender"]      = "SYSTEM",
                ["SenderUid"]   = RealUserId,
                ["Content"]     = emoteMsg,
                ["Server"]      = JobId,
                ["IsSystem"]    = true,
                ["IsAutoClean"] = false,
                ["TargetId"]    = nil,
                ["ReplyTo"]     = nil
            }
            processedKeys[timestamp] = true
            addMessage("SYSTEM", emoteMsg, true, tonumber(timestamp) or 0, 0, false, false, nil)
            task.spawn(function()
                local req = syn and syn.request or http and http.request or request
                if req then req({Url = DATABASE_URL .. "/" .. timestamp .. ".json", Method = "PUT", Body = HttpService:JSONEncode(data)}) end
            end)
            lastMessageTime = os.time()
        end
        return
    end

    -- GAMEBOT GAME SELECTION — intercept "1"-"4" when pending menu choice
    if gameBotPending and not isSystem and (msg == "1" or msg == "2" or msg == "3" or msg == "4") then
        gameBotPending = false
        local gameMap = { ["1"] = "math", ["2"] = "unscramble", ["3"] = "guess", ["4"] = "fill" }
        gameBotStartGame(gameMap[msg])
        return
    end

    if handleLocalCommands(msg) then return end

    -- CREATOR ADMIN COMMANDS (full powers)
    if RealUserId == CREATOR_ID and string.sub(msg, 1, 1) == "/" then
        local cmd = string.lower(args[1])
        local targetName = args[2] or ""
        local target = GetPlayerByName(targetName)

        if cmd == "/kick" and target then
            broadcastCommand(target.UserId, "kick", "Kicked by Ares Creator.")
            return

        -- /ban — CREATOR ONLY — writes to Firebase BAN_URL for permanent ban
        elseif cmd == "/ban" and target then
            task.spawn(function()
                local req = syn and syn.request or http and http.request or request
                if req then
                    pcall(function()
                        req({
                            Url    = BAN_URL .. "/" .. tostring(target.UserId) .. ".json",
                            Method = "PUT",
                            Body   = HttpService:JSONEncode({
                                name        = target.Name,
                                displayName = target.DisplayName,
                                bannedAt    = os.time()
                            })
                        })
                    end)
                end
            end)
            broadcastCommand(target.UserId, "ban", "You are permanently banned from Ares Chat.")
            return

        -- /unban — CREATOR ONLY — removes ban from Firebase
        elseif cmd == "/unban" and args[2] then
            local unbanTarget = GetPlayerByName(args[2])
            local unbanId = nil
            if unbanTarget then
                unbanId = unbanTarget.UserId
            else
                -- Try numeric ID if name not found
                unbanId = tonumber(args[2])
            end
            if unbanId then
                task.spawn(function()
                    local req = syn and syn.request or http and http.request or request
                    if req then
                        pcall(function()
                            req({
                                Url    = BAN_URL .. "/" .. tostring(unbanId) .. ".json",
                                Method = "DELETE"
                            })
                        end)
                    end
                end)
                addMessage("SYSTEM", "Unbanned user ID " .. tostring(unbanId) .. ".", true, 0, 0, false, true)
            else
                addMessage("SYSTEM", "Player or ID not found for /unban.", true, 0, 0, false, true)
            end
            return

        -- /title [name] [colour] [text] — CREATOR ONLY — give a coloured custom title for 1 day
        -- colour must be one of: red, white, yellow, black
        elseif cmd == "/title" and target and args[3] and args[4] then
            local colourArg = string.lower(args[3])
            local titleColourRGB
            if colourArg == "red" then
                titleColourRGB = "rgb(220,50,50)"
            elseif colourArg == "white" then
                titleColourRGB = "rgb(240,240,240)"
            elseif colourArg == "yellow" then
                titleColourRGB = "rgb(255,200,0)"
            elseif colourArg == "black" then
                titleColourRGB = "rgb(40,40,40)"
            else
                addMessage("SYSTEM", "Invalid colour. Use: red, white, yellow, black. Usage: /title [name] [colour] [text]", true, 0, 0, false, true)
                return
            end
            local titleText = table.concat(args, " ", 4)
            local expiresAt = os.time() + 86400  -- 1 day = 86400 seconds
            CustomTitles[target.UserId] = {title = titleText, expiresAt = expiresAt, color = titleColourRGB}
            -- Invalidate TagCache so new title shows immediately
            TagCache[target.UserId] = nil
            -- Write to Firebase so all clients sync the title
            task.spawn(function()
                local req = syn and syn.request or http and http.request or request
                if req then
                    pcall(function()
                        req({
                            Url    = CUSTOM_TITLES_URL .. "/" .. tostring(target.UserId) .. ".json",
                            Method = "PUT",
                            Body   = HttpService:JSONEncode({
                                title       = titleText,
                                expiresAt   = expiresAt,
                                color       = titleColourRGB,
                                name        = target.Name,
                                displayName = target.DisplayName
                            })
                        })
                    end)
                end
            end)
            addMessage("SYSTEM", "Gave [" .. titleText .. "] title (" .. colourArg .. ") to " .. target.DisplayName .. " for 1 day.", true, 0, 0, false, true)
            return

        -- /untitle [name] — CREATOR ONLY — remove custom title instantly
        elseif cmd == "/untitle" and target then
            CustomTitles[target.UserId] = nil
            -- Invalidate TagCache so title is removed immediately on this client
            TagCache[target.UserId] = nil
            -- Delete from Firebase so all other clients sync immediately
            task.spawn(function()
                local req = syn and syn.request or http and http.request or request
                if req then
                    pcall(function()
                        req({
                            Url    = CUSTOM_TITLES_URL .. "/" .. tostring(target.UserId) .. ".json",
                            Method = "DELETE"
                        })
                    end)
                end
            end)
            addMessage("SYSTEM", "Removed custom title from " .. target.DisplayName .. ".", true, 0, 0, false, true)
            return

        elseif cmd == "/kill" and target then broadcastCommand(target.UserId, "kill", "") return
        elseif cmd == "/re" and target then broadcastCommand(target.UserId, "re", "") return
        elseif cmd == "/freeze" and target then broadcastCommand(target.UserId, "freeze", true) return
        elseif cmd == "/unfreeze" and target then broadcastCommand(target.UserId, "freeze", false) return
        elseif cmd == "/make" and args[2] and target then broadcastCommand(target.UserId, "make", args[2]) return
        elseif cmd == "/clear" then cleanDatabase() processedKeys = {} sortedMessageKeys = {} keyToButton = {} return

        elseif cmd == "/speed" and target and args[3] then
            broadcastCommand(target.UserId, "speed", tonumber(args[3])) return

        elseif cmd == "/jump" and target and args[3] then
            broadcastCommand(target.UserId, "jumppower", tonumber(args[3])) return

        elseif cmd == "/tp2me" and target then
            broadcastCommand(target.UserId, "tp2me", RealUserId) return

        elseif cmd == "/invisible" and target then
            broadcastCommand(target.UserId, "invisible", "") return

        elseif cmd == "/mute" and target then
            broadcastCommand(target.UserId, "mute", true) return

        elseif cmd == "/unmute" and target then
            broadcastCommand(target.UserId, "mute", false) return

        elseif cmd == "/announce" then
            local announcement = table.concat(args, " ", 2)
            if announcement ~= "" then
                local ts = string.format("%012d", os.time()) .. math.random(100, 999)
                local pkt = {
                    ["Sender"]      = "SYSTEM",
                    ["SenderUid"]   = 0,
                    ["Content"]     = "📢 ANNOUNCEMENT: " .. announcement,
                    ["Server"]      = "GLOBAL",
                    ["IsSystem"]    = true,
                    ["IsAutoClean"] = false
                }
                local req = syn and syn.request or http and http.request or request
                if req then req({Url = DATABASE_URL .. "/" .. ts .. ".json", Method = "PUT", Body = HttpService:JSONEncode(pkt)}) end
            end
            return
        end
    end

    -- OWNER ADMIN COMMANDS (all except /ban, /unban, /title, /untitle)
    if RealUserId == OWNER_ID and string.sub(msg, 1, 1) == "/" then
        local cmd = string.lower(args[1])
        local targetName = args[2] or ""
        local target = GetPlayerByName(targetName)

        if cmd == "/kick" and target then broadcastCommand(target.UserId, "kick", "Kicked by Ares Owner.") return
        elseif cmd == "/kill" and target then broadcastCommand(target.UserId, "kill", "") return
        elseif cmd == "/re" and target then broadcastCommand(target.UserId, "re", "") return
        elseif cmd == "/freeze" and target then broadcastCommand(target.UserId, "freeze", true) return
        elseif cmd == "/unfreeze" and target then broadcastCommand(target.UserId, "freeze", false) return
        elseif cmd == "/make" and args[2] and target then broadcastCommand(target.UserId, "make", args[2]) return
        elseif cmd == "/clear" then cleanDatabase() processedKeys = {} sortedMessageKeys = {} keyToButton = {} return

        elseif cmd == "/speed" and target and args[3] then
            broadcastCommand(target.UserId, "speed", tonumber(args[3])) return

        elseif cmd == "/jump" and target and args[3] then
            broadcastCommand(target.UserId, "jumppower", tonumber(args[3])) return

        elseif cmd == "/tp2me" and target then
            broadcastCommand(target.UserId, "tp2me", RealUserId) return

        elseif cmd == "/invisible" and target then
            broadcastCommand(target.UserId, "invisible", "") return

        elseif cmd == "/mute" and target then
            broadcastCommand(target.UserId, "mute", true) return

        elseif cmd == "/unmute" and target then
            broadcastCommand(target.UserId, "mute", false) return

        elseif cmd == "/announce" then
            local announcement = table.concat(args, " ", 2)
            if announcement ~= "" then
                local ts = string.format("%012d", os.time()) .. math.random(100, 999)
                local pkt = {
                    ["Sender"]      = "SYSTEM",
                    ["SenderUid"]   = 0,
                    ["Content"]     = "📢 ANNOUNCEMENT: " .. announcement,
                    ["Server"]      = "GLOBAL",
                    ["IsSystem"]    = true,
                    ["IsAutoClean"] = false
                }
                local req = syn and syn.request or http and http.request or request
                if req then req({Url = DATABASE_URL .. "/" .. ts .. ".json", Method = "PUT", Body = HttpService:JSONEncode(pkt)}) end
            end
            return
        end
    end

    -- GAMEBOT HOST ANSWER CHECK — host's own typed messages are processed locally
    -- (processedKeys prevents them from triggering the sync() answer check).
    -- So we check here before the message is sent to Firebase.
    if gameBotActive and gameBotIsHost and gameBotAnswer
        and not isSystem
        and string.lower(msg) == gameBotAnswer then
        gameBotAnswer = nil  -- lock out further wins this round
        gameBotWinCounts[RealDisplayName] = (gameBotWinCounts[RealDisplayName] or 0) + 1
        gameBotWinnerUids[RealDisplayName] = RealUserId
        local sessionWins = gameBotWinCounts[RealDisplayName]
        task.delay(0.3, function()
            gameBotSendSystem("✅ " .. RealDisplayName .. " got it! (" .. sessionWins .. " round win" .. (sessionWins ~= 1 and "s" or "") .. " this session)")
        end)
        task.delay(3, gameBotNextRound)
        -- Still send the message normally so others see what the host typed
    end

    local effectiveTargetId = PrivateTargetId
    local effectivePrivateName = PrivateTargetName

    -- Regular chat message
    local timestamp = string.format("%012d", os.time()) .. math.random(100, 999)
    local replyStr = ReplyTargetName and (ReplyTargetName .. ": " .. (ReplyTargetMsg or "")) or nil
    local data = {
        ["Sender"]      = RealDisplayName,
        ["SenderUid"]   = RealUserId,
        ["Content"]     = msg,
        ["Server"]      = JobId,
        ["IsSystem"]    = isSystem or false,
        ["IsAutoClean"] = isAutoClean or false,
        ["TargetId"]    = effectiveTargetId,
        ["ReplyTo"]     = replyStr
    }
    processedKeys[timestamp] = true
    addMessage(RealDisplayName, msg, isSystem, tonumber(timestamp) or 0, RealUserId, effectiveTargetId ~= nil, false, replyStr)

    ReplyTargetName = nil
    ReplyTargetMsg  = nil
    ReplyBanner.Visible = false
    ReplyLabel.Text = "Replying to ..."

    -- Update last message time for idle detection
    lastMessageTime = os.time()

    task.spawn(function()
        local req = syn and syn.request or http and http.request or request
        if req then req({Url = DATABASE_URL .. "/" .. timestamp .. ".json", Method = "PUT", Body = HttpService:JSONEncode(data)}) end
    end)
end

-- ============================================================
-- SYNC
-- ============================================================
local lastData = ""
local function sync()
    local req = syn and syn.request or http and http.request or request
    if not req then return end
    pcall(function()
        -- limitToLast=25 — only fetch the 25 most recent messages per poll.
        -- This drastically cuts Firebase read bandwidth and stays well within
        -- the free-tier 10 GB/month download limit.
        local res = req({Url = DATABASE_URL .. ".json?orderBy=\"$key\"&limitToLast=25", Method = "GET"})
        if res.Success and res.Body ~= "null" and res.Body ~= lastData then
            lastData = res.Body
            local data = HttpService:JSONDecode(res.Body)
            if data then
                local keys = {}
                for k in pairs(data) do table.insert(keys, k) end
                table.sort(keys)
                for _, k in ipairs(keys) do
                    local msgData = data[k]
                    if not processedKeys[k] then
                        if msgData.Sender == "SYSTEM_CMD" and msgData.TargetId == RealUserId then
                            if msgData.Cmd == "kick" or msgData.Cmd == "ban" then
                                -- Set flag BEFORE kick so no more messages can be sent
                                isKickedOrBanned = true
                                LocalPlayer:Kick(msgData.Val)
                            elseif msgData.Cmd == "kill" then
                                if LocalPlayer.Character then LocalPlayer.Character:BreakJoints() end
                            elseif msgData.Cmd == "re" then
                                LocalPlayer:LoadCharacter()
                            elseif msgData.Cmd == "freeze" then
                                if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                                    LocalPlayer.Character.HumanoidRootPart.Anchored = msgData.Val
                                end
                            elseif msgData.Cmd == "speed" then
                                if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                                    LocalPlayer.Character.Humanoid.WalkSpeed = msgData.Val
                                end
                            elseif msgData.Cmd == "jumppower" then
                                if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                                    LocalPlayer.Character.Humanoid.JumpPower = msgData.Val
                                end
                            elseif msgData.Cmd == "make" then
                                TagCache[RealUserId] = {text = "[" .. string.upper(msgData.Val) .. "] ", type = "Normal"}
                            elseif msgData.Cmd == "tp2me" then
                                -- Teleport to the owner's position
                                local ownerId = tonumber(msgData.Val)
                                if ownerId then
                                    local ownerPlayer = nil
                                    for _, p in pairs(Players:GetPlayers()) do
                                        if p.UserId == ownerId then ownerPlayer = p break end
                                    end
                                    if ownerPlayer and ownerPlayer.Character and ownerPlayer.Character:FindFirstChild("HumanoidRootPart") then
                                        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                                            LocalPlayer.Character.HumanoidRootPart.CFrame = ownerPlayer.Character.HumanoidRootPart.CFrame
                                        end
                                    end
                                end
                            elseif msgData.Cmd == "invisible" then
                                if LocalPlayer.Character then
                                    IsInvisible = not IsInvisible
                                    for _, part in pairs(LocalPlayer.Character:GetDescendants()) do
                                        if part:IsA("BasePart") or part:IsA("Decal") then
                                            part.Transparency = IsInvisible and 1 or 0
                                        end
                                    end
                                end
                            elseif msgData.Cmd == "mute" then
                                -- MUTE HANDLER: store mute state in MutedPlayers table.
                                -- val=true → muted (suppress GUI, bubble, Firebase display).
                                -- val=false → unmuted (restore all display).
                                -- TargetId here is the person being muted — stored so that
                                -- all clients who see this command suppress that player's messages.
                                MutedPlayers[msgData.TargetId] = (msgData.Val == true)
                            end
                        end

                        -- MUTE BROADCAST: when a SYSTEM_CMD mute is received from another user,
                        -- ALL clients need to apply it (not just the muted player's client).
                        -- This block handles the case where the command is for a DIFFERENT player.
                        if msgData.Sender == "SYSTEM_CMD" and msgData.Cmd == "mute" then
                            MutedPlayers[msgData.TargetId] = (msgData.Val == true)
                        end

                        -- Show message if it's from THIS server OR if it's a GLOBAL announcement
                        -- Skip messages that have been deleted (IsDeleted=true) or are empty unsent stubs
                        if (msgData.Server == JobId or msgData.Server == "GLOBAL") and msgData.Sender ~= "SYSTEM_CMD" and not msgData.IsDeleted and not msgData.IsDM then
                            local isPrivate = msgData.TargetId ~= nil
                            local canSee = not isPrivate or (msgData.TargetId == RealUserId or msgData.SenderUid == RealUserId)
                            if canSee then
                                -- Skip muted players' messages for everyone else
                                local senderMuted = (not msgData.IsSystem) and MutedPlayers[msgData.SenderUid]
                                if not senderMuted then
                                    local isAutoClean = msgData.IsAutoClean or false
                                    addMessage(msgData.Sender, msgData.Content, msgData.IsSystem, tonumber(k) or 0, msgData.SenderUid, isPrivate, false, msgData.ReplyTo)

                                    -- GAMEBOT ANSWER CHECK — host only judges winner
                                    if gameBotActive and gameBotIsHost and gameBotAnswer
                                        and not msgData.IsSystem
                                        and msgData.SenderUid ~= 0
                                        and string.lower(msgData.Content or "") == gameBotAnswer then
                                        local winnerName = msgData.Sender or "Unknown"
                                        local winnerUid  = msgData.SenderUid or 0
                                        gameBotAnswer    = nil  -- lock out further wins this round
                                        gameBotWinCounts[winnerName] = (gameBotWinCounts[winnerName] or 0) + 1
                                        gameBotWinnerUids[winnerName] = winnerUid  -- store uid for end-of-game trophy
                                        -- Announce round win (no trophy award yet — only at end)
                                        local sessionWins = gameBotWinCounts[winnerName]
                                        task.delay(0.3, function()
                                            gameBotSendSystem("✅ " .. winnerName .. " got it! (" .. sessionWins .. " round win" .. (sessionWins ~= 1 and "s" or "") .. " this session)")
                                        end)
                                        -- Advance to next round
                                        task.delay(3, gameBotNextRound)
                                    end

                                    if msgData.SenderUid ~= RealUserId then
                                        -- Show notification for all messages; truncate content to first 80 characters
                                        local notifContent = msgData.Content or ""
                                        -- Show friendly label for sticker messages in notifications
                                        if string.match(notifContent, "^%[STICKER:%d+%]$") then
                                            notifContent = "🎭 Sent a sticker"
                                        elseif #notifContent > 80 then
                                            notifContent = string.sub(notifContent, 1, 80)
                                        end
                                        createNotification(msgData.Sender, notifContent, isPrivate, msgData.IsSystem, msgData.SenderUid, isAutoClean)
                                    end
                                    -- Update idle timer whenever a new message arrives from Firebase
                                    lastMessageTime = os.time()
                                end
                            end
                        end
                        processedKeys[k] = true
                    elseif msgData then
                        -- --------------------------------------------------------
                        -- UNSEND propagation: another client unsent a message we
                        -- already rendered — destroy its wrapper frame.
                        -- --------------------------------------------------------
                        if msgData.IsDeleted and keyToButton[k] then
                            local btn = keyToButton[k]
                            local wf  = btn and btn.Parent
                            keyToButton[k] = nil
                            if btn then SpecialLabels[btn] = nil end
                            if btn then NormalTitleLabels[btn] = nil end
                            local newKeys = {}
                            for _, sk in ipairs(sortedMessageKeys) do
                                if sk ~= k then table.insert(newKeys, sk) end
                            end
                            sortedMessageKeys = newKeys
                            if wf and wf.Parent then wf:Destroy() end
                        end
                        -- --------------------------------------------------------
                        -- EDIT PROPAGATION: another client patched a message we
                        -- already rendered — update its bubble text instantly.
                        -- --------------------------------------------------------
                        if not msgData.IsDeleted and keyToButton[k] and msgData.Content then
                            local btn = keyToButton[k]
                            local safeEditMsg = SafeEncodeMsg(msgData.Content)
                            if SpecialLabels[btn] then
                                SpecialLabels[btn].msg = safeEditMsg
                            elseif NormalTitleLabels[btn] then
                                NormalTitleLabels[btn].msg = safeEditMsg
                            else
                                local cur = btn and btn.Text or ""
                                local colonPos = string.find(cur, ": ", 1, true)
                                if colonPos then
                                    local newText = string.sub(cur, 1, colonPos+1) .. safeEditMsg
                                    if newText ~= cur then
                                        btn.Text = newText
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
end

-- ============================================================
-- SYNC ONLINE REGISTRY
-- ============================================================
local function syncOnline()
    local req = syn and syn.request or http and http.request or request
    if not req then return end
    pcall(function()
        local res = req({Url = ONLINE_URL .. "/" .. JobId .. ".json", Method = "GET"})
        if res.Success and res.Body ~= "null" then
            local onlineData = HttpService:JSONDecode(res.Body)
            if type(onlineData) == "table" then
                for uid, _ in pairs(onlineData) do
                    scriptUsersInServer[tonumber(uid)] = true
                end
            end
        end
    end)
end

-- ============================================================
-- SYNC CUSTOM TITLES FROM FIREBASE (called periodically)
-- Ensures all clients have up-to-date custom titles.
-- ============================================================
local function syncCustomTitles()
    local req = syn and syn.request or http and http.request or request
    if not req then return end
    pcall(function()
        local res = req({Url = CUSTOM_TITLES_URL .. ".json", Method = "GET"})
        if res and res.Success and res.Body ~= "null" then
            local ok, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
            if ok and type(data) == "table" then
                local now = os.time()
                local changed = false
                for uidStr, entry in pairs(data) do
                    local uid = tonumber(uidStr)
                    if uid and type(entry) == "table" then
                        if entry.expiresAt and entry.expiresAt > now then
                            local existing = CustomTitles[uid]
                            if not existing or existing.title ~= entry.title or existing.expiresAt ~= entry.expiresAt then
                                CustomTitles[uid] = {title = entry.title, expiresAt = entry.expiresAt, color = entry.color}
                                TagCache[uid] = nil  -- force re-cache so new title shows
                                changed = true
                            end
                        else
                            -- Title expired — remove
                            if CustomTitles[uid] then
                                CustomTitles[uid] = nil
                                TagCache[uid] = nil
                                changed = true
                            end
                        end
                    end
                end
                -- Also check for titles removed from Firebase (untitle command)
                for uid, _ in pairs(CustomTitles) do
                    if not data[tostring(uid)] then
                        CustomTitles[uid] = nil
                        TagCache[uid] = nil
                        changed = true
                    end
                end
            end
        elseif res and res.Success and res.Body == "null" then
            -- All titles cleared from Firebase
            for uid, _ in pairs(CustomTitles) do
                CustomTitles[uid] = nil
                TagCache[uid] = nil
            end
        end
    end)
end

-- ============================================================
-- FIREBASE DYNAMIC BAN CHECK
-- Checks the /bans Firebase node periodically.
-- Sets isKickedOrBanned to block further sends; does NOT call Kick()
-- to prevent crash/rejoin loops caused by transient Firebase errors.
-- ============================================================
task.spawn(function()
    task.wait(5)  -- stagger after other startup HTTP requests
    while true do
        pcall(function()
            local req = syn and syn.request or http and http.request or request
            if req then
                local res = req({Url = BAN_URL .. "/" .. tostring(RealUserId) .. ".json", Method = "GET"})
                if res and res.Success and res.Body ~= "null" and res.Body ~= "" and res.Body ~= "false" then
                    isKickedOrBanned = true
                    -- Block message sending — no Kick() to avoid crash/rejoin loop
                end
            end
        end)
        task.wait(60)  -- re-check every 60 seconds (was 15 — reduces HTTP load)
    end
end)

-- ============================================================
-- TOGGLE + INPUT HANDLERS
-- ============================================================
ToggleBtn.MouseButton1Click:Connect(function()
    -- If the user just dragged the button, don't toggle — just reset the flag.
    if toggleDragMoved then
        toggleDragMoved = false
        return
    end
    Main.Visible = not Main.Visible
    ToggleBtn.Text = Main.Visible and "X" or "*"
end)

MinimizeBtn.MouseButton1Click:Connect(function()
    Main.Visible = false
    ToggleBtn.Text = "*"
end)

Input.FocusLost:Connect(function(enter)
    if enter then
        local txt = Input.Text
        Input.Text = ""
        send(txt, false, false)
    end
end)

SendBtn.MouseButton1Click:Connect(function()
    local txt = Input.Text
    Input.Text = ""
    send(txt, false, false)
end)



-- ============================================================
-- REGISTER THIS PLAYER IN ONLINE REGISTRY
-- ============================================================
task.spawn(function()
    local req = syn and syn.request or http and http.request or request
    if req then
        local uid = tostring(RealUserId)
        pcall(function()
            req({
                Url = ONLINE_URL .. "/" .. JobId .. "/" .. uid .. ".json",
                Method = "PUT",
                Body = HttpService:JSONEncode(RealDisplayName)
            })
        end)
        scriptUsersInServer[RealUserId] = true
    end
end)

task.spawn(function()
    task.wait(1)
    syncOnline()
end)

-- ============================================================
-- FRESH START: Clear local UI on join so player sees a clean
-- window without stale pre-arrival history cluttering the view.
-- Does NOT wipe Firebase — server history is preserved.
-- ============================================================
task.spawn(function()
    task.wait(1.5)
    for _, child in pairs(ChatLog:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end  -- wrapperFrames (not UIListLayout)
    end
    sortedMessageKeys = {}
    keyToButton = {}
    -- Do NOT reset processedKeys — we don't want to re-render old messages
end)

local function showUpdateOverlay()
    local updateOverlay = Instance.new("Frame", ScreenGui)
    updateOverlay.Size = Main.Size
    updateOverlay.Position = Main.Position
    updateOverlay.AnchorPoint = Main.AnchorPoint
    updateOverlay.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    updateOverlay.BackgroundTransparency = 0.0
    updateOverlay.BorderSizePixel = 0
    updateOverlay.ZIndex = 800
    updateOverlay.ClipsDescendants = true
    Instance.new("UICorner", updateOverlay).CornerRadius = UDim.new(0, 16)
    local updateStroke = Instance.new("UIStroke", updateOverlay)
    updateStroke.Color = Color3.fromRGB(225, 48, 108)
    updateStroke.Thickness = 1.6

    local title = Instance.new("TextLabel", updateOverlay)
    title.Size = UDim2.new(1, -28, 0, 34)
    title.Position = UDim2.new(0, 14, 0, 14)
    title.BackgroundTransparency = 1
    title.Text = "Ares ReChat V31 Update"
    title.TextColor3 = Color3.fromRGB(225, 48, 108)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 17
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 801

    local body = Instance.new("TextLabel", updateOverlay)
    body.Size = UDim2.new(1, -28, 1, -110)
    body.Position = UDim2.new(0, 14, 0, 54)
    body.BackgroundTransparency = 1
    body.Text = "Latest update:\n• Tap any profile picture or username to open profile.\n• 10 FOLLOWER = Premium Title.\n• 50 FOLLOWERS = Legend Title.\n• 100 FOLLOWERS = VIP Title.\n• New light and dark theme button side of lock button.\n\nUsage:\n• Swipe a message to reply.\n• Hold a message for actions.\n• Use /commands to view all commands.\n\nContact:\n• Insta = iam_honored_0ne.\n• Discord = ares.oldz."
    body.TextColor3 = Color3.fromRGB(40, 40, 40)
    body.Font = Enum.Font.GothamBold
    body.TextSize = 15
    body.TextWrapped = true
    body.TextXAlignment = Enum.TextXAlignment.Left
    body.TextYAlignment = Enum.TextYAlignment.Top
    body.ZIndex = 801

    local continueBtn = Instance.new("TextButton", updateOverlay)
    continueBtn.Size = UDim2.new(1, -28, 0, 36)
    continueBtn.Position = UDim2.new(0, 14, 1, -50)
    continueBtn.BackgroundColor3 = Color3.fromRGB(225, 48, 108)
    continueBtn.BackgroundTransparency = 0.0
    continueBtn.BorderSizePixel = 0
    continueBtn.Text = "Continue"
    continueBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    continueBtn.Font = Enum.Font.GothamBold
    continueBtn.TextSize = 14
    continueBtn.ZIndex = 801
    Instance.new("UICorner", continueBtn).CornerRadius = UDim.new(0, 9)
    continueBtn.MouseButton1Click:Connect(function()
        TweenService:Create(updateOverlay, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency = 1}):Play()
        task.delay(0.18, function()
            if updateOverlay and updateOverlay.Parent then updateOverlay:Destroy() end
        end)
    end)
end

task.spawn(function()
    showUpdateOverlay()
end)

-- ============================================================
-- JOIN MESSAGE — fetches badge first, then posts to Firebase.
-- Badge image marker appended right of display name in join message.
-- ============================================================
task.spawn(function()
    -- Fetch own follower count first so follower title can be included in join message
    local myTitle = ""
    pcall(function()
        local req = syn and syn.request or http and http.request or request
        if req then
            local res = req({ Url = FOLLOWERS_URL .. "/" .. tostring(RealUserId) .. ".json", Method = "GET" })
            if res and res.Success and res.Body ~= "null" then
                local ok, fdata = pcall(HttpService.JSONDecode, HttpService, res.Body)
                if ok and type(fdata) == "table" then
                    local count = 0
                    for _ in pairs(fdata) do count = count + 1 end
                    badgeCache[RealUserId] = count
                    followerCountCache[RealUserId] = count
                    -- Only add follower title if user has no hardcoded tag
                    local hasHardcoded = (RealUserId == CREATOR_ID or RealUserId == OWNER_ID
                        or CUTE_IDS[RealUserId] or HELLGOD_IDS[RealUserId]
                        or VIP_IDS[RealUserId] or GOD_IDS[RealUserId]
                        or DADDY_IDS[RealUserId] or REAPER_IDS[RealUserId]
                        or PAPA_MVP_IDS[RealUserId])
                    if not hasHardcoded then
                        myTitle = getFollowerTitleFromCount(count)
                    end
                end
            end
        end
    end)

    local joinMsg = RealDisplayName .. myTitle .. " joined the chat!"
    if RealUserId == CREATOR_ID then
        joinMsg = "⚡ [ᴄʀᴇᴀᴛᴏʀ] ⚡ THE ALMIGHTY CREATOR " .. RealDisplayName:upper() .. " HAS DESCENDED UPON THIS REALM! THE ARCHITECT OF ARES IS PRESENT! ALL SHALL WITNESS! ⚡"
    elseif RealUserId == OWNER_ID then
        joinMsg = "👑 [◎ẘη℮ґ] THE SUPREME OWNER HAS ARRIVED! ALL HAIL " .. RealDisplayName:upper() .. "! BOW DOWN BEFORE THE ◎ẘη℮ґ! 👑"
    elseif CUTE_IDS[RealUserId] then
        joinMsg = "[CUTE] THE CUTEST PERSON " .. RealDisplayName:upper() .. " HAS JOINED!"
    elseif HELLGOD_IDS[RealUserId] then
        joinMsg = "🔥 [HellGod] THE HELLGOD " .. RealDisplayName:upper() .. " HAS RISEN FROM THE DEPTHS! TREMBLE BEFORE THEM! 🔥"
    elseif GOD_IDS[RealUserId] then
        joinMsg = "⚫ [GOD] THE GOD " .. RealDisplayName:upper() .. " HAS ARRIVED! ALL SHALL KNEEL! ⚫"
    elseif DADDY_IDS[RealUserId] then
        joinMsg = "💜 [DADDY] " .. RealDisplayName:upper() .. " HAS JOINED THE CHAT!"
    elseif REAPER_IDS[RealUserId] then
        joinMsg = "💀 [REAPER] THE REAPER " .. RealDisplayName:upper() .. " HAS ARRIVED! FEAR THE REAPER! 💀"
    elseif PAPA_MVP_IDS[RealUserId] then
        joinMsg = "👑 [PAPA MVP] THE PAPA MVP " .. RealDisplayName:upper() .. " HAS ARRIVED! ALL HAIL THE PAPA MVP! 👑"
    elseif VIP_IDS[RealUserId] then
        joinMsg = "[VIP] THE VIP " .. RealDisplayName:upper() .. " HAS JOINED!"
    end

    local joinTimestamp = string.format("%012d", os.time()) .. math.random(100, 999)
    local joinPacket = {
        ["Sender"]      = "SYSTEM",
        ["SenderUid"]   = 0,
        ["Content"]     = joinMsg,
        ["Server"]      = JobId,
        ["IsSystem"]    = true,
        ["IsAutoClean"] = false
    }
    local req = syn and syn.request or http and http.request or request
    if req then req({Url = DATABASE_URL .. "/" .. joinTimestamp .. ".json", Method = "PUT", Body = HttpService:JSONEncode(joinPacket)}) end
end)

-- ============================================================
-- LEAVE MESSAGE REMOVED (by request)
-- PlayerRemoving no longer posts any system message.
-- Online registry is still cleaned up silently.
-- ============================================================
Players.PlayerRemoving:Connect(function(player)
    if player ~= LocalPlayer then return end
    scriptUsersInServer[player.UserId] = nil
    task.spawn(function()
        local req = syn and syn.request or http and http.request or request
        if req then
            pcall(function()
                req({
                    Url = ONLINE_URL .. "/" .. JobId .. "/" .. tostring(player.UserId) .. ".json",
                    Method = "DELETE"
                })
            end)
        end
    end)
    -- NO leave message written to Firebase
end)

-- ============================================================
-- MUSIC PLAYER — Creator-Only (MUSIC tab)
-- Uses SoundCloud API (same as spotify.lua) to search and play.
-- When Creator hits Play: stream URL is broadcast via Firebase
-- so ALL script users in the same server play the same song.
-- Non-creator users: a silent background loop checks Firebase
-- every 2s and plays whatever the Creator is broadcasting.
-- ============================================================

local MUSIC_SC_CLIENT_ID = "RF8yvumNwWwVg0aX4r7fHqzIVAtO6nSI"
local musicCurrentResults = {}
local musicCurrentIndex   = 0
local musicCurrentTrack   = nil
local musicIsPlaying      = false
local musicIsPaused       = false
local musicIsBusy         = false
local musicTrackToken     = 0
local musicProgressConn   = nil
local musicEndedConn      = nil
local musicShuffleOn      = false
local musicLoopOn         = false
local musicAudioPlayer    = nil   -- created on first use (Sound in SoundService)
local musicLastBroadcastUrl = ""  -- tracks what we last broadcast
local musicVolLevels      = { 1, 0.75, 0.5, 0.25 }
local musicVolIdx         = 1
local musicIsSeeking      = false
local musicCurrentQuery   = ""   -- last search query (for Load More)
local musicCurrentOffset  = 0    -- current SoundCloud result offset

-- Audio player for creator & listener
local function getMusicAudioPlayer()
    if not musicAudioPlayer or not musicAudioPlayer.Parent then
        musicAudioPlayer = Instance.new("Sound")
        musicAudioPlayer.Parent = game:GetService("SoundService")
        musicAudioPlayer.Volume = 1
        musicAudioPlayer.Name   = "AresMusicPlayer"
    end
    return musicAudioPlayer
end

local function musicFormatTime(secs)
    secs = math.floor(tonumber(secs) or 0)
    return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

local function musicSafeGet(url)
    if not url or url == "" then return nil end
    local req = syn and syn.request or http and http.request or request
    if not req then return nil end
    local ok, res = pcall(function() return req({ Url = url, Method = "GET" }) end)
    if not ok or not res then return nil end
    local statusOk = res.Success or (type(res.StatusCode) == "number" and res.StatusCode >= 200 and res.StatusCode < 300)
    if not statusOk or not res.Body or #res.Body == 0 then return nil end
    return res.Body
end

local function musicDownloadFile(url, path)
    local body = musicSafeGet(url)
    if not body then return nil end
    local ok = pcall(writefile, path, body)
    if not ok then return nil end
    task.wait(0.08)
    local asset
    pcall(function() asset = getcustomasset(path) end)
    return asset
end

local function musicStopProgressLoop()
    if musicProgressConn then
        pcall(function() musicProgressConn:Disconnect() end)
        musicProgressConn = nil
    end
end

local function musicStartProgressLoop()
    musicStopProgressLoop()
    local ap = getMusicAudioPlayer()
    local accum = 0
    musicProgressConn = RunService.Heartbeat:Connect(function(dt)
        accum = accum + dt
        if accum < 0.1 then return end
        accum = 0
        if musicIsSeeking then return end
        if not ap or not ap.IsPlaying then return end
        local len = ap.TimeLength
        local pos = ap.TimePosition
        if len and len > 0 then
            local ratio = math.clamp(pos / len, 0, 1)
            if MusicProgressFill and MusicProgressFill.Parent then
                MusicProgressFill.Size = UDim2.new(ratio, 0, 1, 0)
            end
            if MusicSeekKnob and MusicSeekKnob.Parent then
                MusicSeekKnob.Position = UDim2.new(ratio, 0, 0.5, 0)
            end
            if MusicTimeLeft and MusicTimeLeft.Parent then
                MusicTimeLeft.Text = musicFormatTime(pos)
            end
            if MusicTimeRight and MusicTimeRight.Parent then
                MusicTimeRight.Text = musicFormatTime(len)
            end
        end
    end)
end

local function musicSetProgressVisible(v)
    if MusicProgressBG  and MusicProgressBG.Parent  then MusicProgressBG.Visible  = v end
    if MusicTimeLeft    and MusicTimeLeft.Parent    then MusicTimeLeft.Visible     = v end
    if MusicTimeRight   and MusicTimeRight.Parent   then MusicTimeRight.Visible    = v end
    if not v and MusicSeekKnob and MusicSeekKnob.Parent then MusicSeekKnob.Visible = false end
end

local function musicResetProgress()
    if MusicProgressFill and MusicProgressFill.Parent then
        MusicProgressFill.Size = UDim2.new(0, 0, 1, 0)
    end
    if MusicSeekKnob and MusicSeekKnob.Parent then
        MusicSeekKnob.Position = UDim2.new(0, 0, 0.5, 0)
    end
    if MusicTimeLeft  and MusicTimeLeft.Parent  then MusicTimeLeft.Text  = "0:00" end
    if MusicTimeRight and MusicTimeRight.Parent then MusicTimeRight.Text = "0:00" end
end

local function musicSetPlayState(state)
    if not (MusicPlayBtn and MusicPlayBtn.Parent) then return end
    if state == "idle" then
        MusicPlayBtn.Text             = "▶ Play & Broadcast"
        MusicPlayBtn.BackgroundColor3 = Color3.fromRGB(30, 215, 96)
        musicIsPlaying = false; musicIsPaused = false; musicIsBusy = false
        if MusicSeekKnob and MusicSeekKnob.Parent then MusicSeekKnob.Visible = false end
    elseif state == "loading" then
        MusicPlayBtn.Text             = "⏳ Loading..."
        MusicPlayBtn.BackgroundColor3 = Color3.fromRGB(200, 150, 0)
        musicIsBusy = true
    elseif state == "playing" then
        MusicPlayBtn.Text             = "⏸ Pause"
        MusicPlayBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
        musicIsPlaying = true; musicIsPaused = false; musicIsBusy = false
        if MusicSeekKnob and MusicSeekKnob.Parent then MusicSeekKnob.Visible = true end
    elseif state == "paused" then
        MusicPlayBtn.Text             = "▶ Resume"
        MusicPlayBtn.BackgroundColor3 = Color3.fromRGB(30, 215, 96)
        musicIsPlaying = false; musicIsPaused = true; musicIsBusy = false
        if MusicSeekKnob and MusicSeekKnob.Parent then MusicSeekKnob.Visible = true end
    elseif state == "error" then
        MusicPlayBtn.Text             = "⚠ Error"
        MusicPlayBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
        musicIsPlaying = false; musicIsPaused = false; musicIsBusy = false
        if MusicSeekKnob and MusicSeekKnob.Parent then MusicSeekKnob.Visible = false end
        task.delay(2.5, function()
            if not musicIsPlaying and not musicIsBusy then
                musicSetPlayState("idle")
            end
        end)
    end
end

-- Populate track info + load thumbnail async
local function musicPopulateTrackInfo(track)
    if type(track) ~= "table" then return end

    musicTrackToken = musicTrackToken + 1
    local myToken = musicTrackToken

    musicStopProgressLoop()
    if musicEndedConn then
        pcall(function() musicEndedConn:Disconnect() end)
        musicEndedConn = nil
    end
    local ap = getMusicAudioPlayer()
    pcall(function() ap:Stop() end)
    pcall(function() ap.SoundId = "" end)

    musicCurrentTrack = track

    if MusicSongTitle and MusicSongTitle.Parent then
        MusicSongTitle.Text = "🎵 " .. tostring(track.title or "Unknown")
    end
    if MusicSongDuration and MusicSongDuration.Parent then
        MusicSongDuration.Text = "⏱ " .. musicFormatTime(track.duration or 0)
    end

    musicResetProgress()
    if MusicTimeRight and MusicTimeRight.Parent then
        MusicTimeRight.Text = musicFormatTime(track.duration or 0)
    end
    musicSetProgressVisible(true)
    if MusicSeekKnob and MusicSeekKnob.Parent then MusicSeekKnob.Visible = false end

    -- Back button visible when results exist
    if MusicBackBtn and MusicBackBtn.Parent then
        MusicBackBtn.Visible = (#musicCurrentResults > 0)
    end

    -- Show thumbnail, hide results panel
    if MusicThumbnail and MusicThumbnail.Parent then
        MusicThumbnail.Image   = ""
        MusicThumbnail.Visible = true
        if MusicThumbPlaceholder and MusicThumbPlaceholder.Parent then
            MusicThumbPlaceholder.Visible = true
        end
    end
    if MusicResultsPanel and MusicResultsPanel.Parent then
        MusicResultsPanel.Visible = false
    end

    -- Async thumbnail load
    if type(track.thumbnail) == "string" and track.thumbnail ~= "" then
        local thumbUrl = track.thumbnail
        task.spawn(function()
            pcall(function() makefolder("ares music") end)
            local uniquePath = "ares music/music_thumb_" .. tostring(myToken) .. ".png"
            local asset = musicDownloadFile(thumbUrl, uniquePath)
            if myToken ~= musicTrackToken then return end
            if asset and MusicThumbnail and MusicThumbnail.Parent then
                MusicThumbnail.Image = asset
                if MusicThumbPlaceholder and MusicThumbPlaceholder.Parent then
                    MusicThumbPlaceholder.Visible = false
                end
            end
            -- Clean up previous thumb file
            pcall(function()
                if delfile then
                    delfile("ares music/music_thumb_" .. tostring(myToken - 1) .. ".png")
                end
            end)
        end)
    end

    musicSetPlayState("idle")
end

-- Fetch SoundCloud progressive stream URL from a track object
local function musicFetchTrackStream(trackObj)
    if not trackObj or not trackObj.media or not trackObj.media.transcodings then
        return nil, "No media"
    end
    local progressiveUrl
    for _, trans in ipairs(trackObj.media.transcodings) do
        if trans.format and trans.format.protocol == "progressive" then
            progressiveUrl = trans.url
            break
        end
    end
    if not progressiveUrl then return nil, "No direct MP3 stream" end
    local body = musicSafeGet(progressiveUrl .. "?client_id=" .. MUSIC_SC_CLIENT_ID)
    if not body then return nil, "Stream fetch failed" end
    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok or type(data) ~= "table" or not data.url then return nil, "Bad stream data" end
    return data.url, nil
end

-- Broadcast the currently playing song to Firebase so all server users hear it
local function musicBroadcastPlay(streamUrl, title)
    local req = syn and syn.request or http and http.request or request
    if not req then return end
    musicLastBroadcastUrl = streamUrl
    local payload = {
        Action    = "play",
        StreamUrl = streamUrl,
        Title     = title or "Unknown",
        Server    = JobId,
        StartedAt = os.time()
    }
    pcall(function()
        req({
            Url    = MUSIC_SYNC_URL .. "/" .. JobId .. ".json",
            Method = "PUT",
            Body   = HttpService:JSONEncode(payload)
        })
    end)
end

-- Broadcast stop (clears Firebase entry for this server)
local function musicBroadcastStop()
    local req = syn and syn.request or http and http.request or request
    if not req then return end
    musicLastBroadcastUrl = ""
    pcall(function()
        req({ Url = MUSIC_SYNC_URL .. "/" .. JobId .. ".json", Method = "DELETE" })
    end)
end

-- Core play routine (Creator only)
local function musicPlayCurrentTrack()
    if not musicCurrentTrack or not musicCurrentTrack.sc_track then return end
    local myToken = musicTrackToken

    task.spawn(function()
        musicSetPlayState("loading")

        musicStopProgressLoop()
        if musicEndedConn then
            pcall(function() musicEndedConn:Disconnect() end)
            musicEndedConn = nil
        end
        local ap = getMusicAudioPlayer()
        pcall(function() ap:Stop() end)
        pcall(function() ap.SoundId = "" end)
        musicResetProgress()
        musicSetProgressVisible(true)

        local streamUrl, err = musicFetchTrackStream(musicCurrentTrack.sc_track)
        if myToken ~= musicTrackToken then return end
        if not streamUrl then
            musicSetPlayState("error")
            if MusicPlayBtn and MusicPlayBtn.Parent then
                MusicPlayBtn.Text = "⚠ " .. tostring(err)
            end
            return
        end

        -- Try to cache locally first, then stream directly
        if MusicPlayBtn and MusicPlayBtn.Parent then MusicPlayBtn.Text = "⏳ Caching..." end
        pcall(function() makefolder("ares music") end)
        local audioAsset = musicDownloadFile(streamUrl, "ares music/music_creator.mp3")
        if myToken ~= musicTrackToken then return end

        local setOk = false
        if audioAsset then
            setOk = pcall(function() ap.SoundId = audioAsset end)
        end
        if not setOk then
            if MusicPlayBtn and MusicPlayBtn.Parent then MusicPlayBtn.Text = "⏳ Streaming..." end
            pcall(function() ap.SoundId = streamUrl end)
        end

        pcall(function() ap.TimePosition = 0 end)
        pcall(function() ap:Play() end)
        musicSetPlayState("playing")
        musicStartProgressLoop()

        -- Broadcast stream URL to all server users
        local broadcastTitle = musicCurrentTrack and musicCurrentTrack.title or "Unknown"
        task.spawn(function() musicBroadcastPlay(streamUrl, broadcastTitle) end)

        -- Send a chat notification to server
        task.spawn(function()
            local ts = string.format("%012d", os.time()) .. math.random(100, 999)
            local pkt = {
                ["Sender"]      = "SYSTEM",
                ["SenderUid"]   = 0,
                ["Content"]     = "🎵 Creator is now playing: " .. broadcastTitle,
                ["Server"]      = JobId,
                ["IsSystem"]    = true,
                ["IsAutoClean"] = false
            }
            local req2 = syn and syn.request or http and http.request or request
            if req2 then
                pcall(function()
                    req2({ Url = DATABASE_URL .. "/" .. ts .. ".json", Method = "PUT", Body = HttpService:JSONEncode(pkt) })
                end)
            end
        end)

        -- Auto-advance on track end
        musicEndedConn = ap.Ended:Connect(function()
            if musicEndedConn then
                pcall(function() musicEndedConn:Disconnect() end)
                musicEndedConn = nil
            end
            musicStopProgressLoop()
            musicResetProgress()
            musicIsPaused = false
            musicSetPlayState("idle")
            musicBroadcastStop()

            if musicLoopOn then
                task.defer(musicPlayCurrentTrack)
            elseif musicShuffleOn and #musicCurrentResults > 1 then
                local newIdx
                repeat newIdx = math.random(1, #musicCurrentResults) until newIdx ~= musicCurrentIndex
                musicCurrentIndex = newIdx
                musicPopulateTrackInfo(musicCurrentResults[musicCurrentIndex])
                task.defer(musicPlayCurrentTrack)
            elseif #musicCurrentResults > 0 and musicCurrentIndex < #musicCurrentResults then
                musicCurrentIndex = musicCurrentIndex + 1
                musicPopulateTrackInfo(musicCurrentResults[musicCurrentIndex])
                task.defer(musicPlayCurrentTrack)
            end
        end)
    end)
end

-- Search handler (Creator only)
if RealUserId == CREATOR_ID then
    local function musicClearResults()
        for _, c in ipairs(MusicResultsPanel:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
    end

    local function musicShowResults(results, appendMode)
        if not appendMode then
            musicClearResults()
        else
            -- Remove existing Load More button before appending
            for _, c in ipairs(MusicResultsPanel:GetChildren()) do
                if c:IsA("TextButton") and c.Name == "LoadMoreBtn" then c:Destroy() end
            end
        end
        MusicResultsPanel.Visible = true
        MusicThumbnail.Visible = false
        local startIdx = appendMode and (#musicCurrentResults - #results + 1) or 1
        for i, track in ipairs(results) do
            local globalIdx = appendMode and (startIdx + i - 1) or i
            local row = Instance.new("TextButton", MusicResultsPanel)
            row.LayoutOrder     = globalIdx
            row.Size            = UDim2.new(1, 0, 0, 22)
            row.BackgroundColor3 = Color3.fromRGB(32, 32, 32)
            row.TextColor3      = Color3.new(1, 1, 1)
            row.Font            = Enum.Font.Gotham
            row.TextSize        = 10
            row.TextXAlignment  = Enum.TextXAlignment.Left
            row.TextTruncate    = Enum.TextTruncate.AtEnd
            row.Text            = "  " .. globalIdx .. ". " .. (track.title or "Unknown")
            row.ZIndex          = 3
            row.BorderSizePixel = 0
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)
            row.MouseEnter:Connect(function() row.BackgroundColor3 = Color3.fromRGB(50, 50, 50) end)
            row.MouseLeave:Connect(function() row.BackgroundColor3 = Color3.fromRGB(32, 32, 32) end)
            local boundIdx = globalIdx
            row.MouseButton1Click:Connect(function()
                MusicResultsPanel.Visible = false
                musicCurrentIndex = boundIdx
                musicPopulateTrackInfo(musicCurrentResults[boundIdx])
            end)
        end

        -- Load More button at the bottom
        local loadMoreBtn = Instance.new("TextButton", MusicResultsPanel)
        loadMoreBtn.Name           = "LoadMoreBtn"
        loadMoreBtn.LayoutOrder    = 99999
        loadMoreBtn.Size           = UDim2.new(1, 0, 0, 22)
        loadMoreBtn.BackgroundColor3 = Color3.fromRGB(50, 100, 60)
        loadMoreBtn.TextColor3     = Color3.new(1, 1, 1)
        loadMoreBtn.Font           = Enum.Font.GothamBold
        loadMoreBtn.TextSize       = 10
        loadMoreBtn.Text           = "⬇ Load More Songs"
        loadMoreBtn.ZIndex         = 3
        loadMoreBtn.BorderSizePixel = 0
        Instance.new("UICorner", loadMoreBtn).CornerRadius = UDim.new(0, 4)
        loadMoreBtn.MouseButton1Click:Connect(function()
            if not musicCurrentQuery or musicCurrentQuery == "" then return end
            loadMoreBtn.Text = "⏳ Loading..."
            loadMoreBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
            local nextOffset = musicCurrentOffset + 20
            task.spawn(function()
                local searchUrl = "https://api-v2.soundcloud.com/search/tracks?q="
                    .. HttpService:UrlEncode(musicCurrentQuery)
                    .. "&client_id=" .. MUSIC_SC_CLIENT_ID
                    .. "&limit=20&offset=" .. tostring(nextOffset)
                local body = musicSafeGet(searchUrl)
                if not body then
                    loadMoreBtn.Text = "⚠ Error — try again"
                    loadMoreBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
                    task.delay(2, function()
                        if loadMoreBtn and loadMoreBtn.Parent then
                            loadMoreBtn.Text = "⬇ Load More Songs"
                            loadMoreBtn.BackgroundColor3 = Color3.fromRGB(50, 100, 60)
                        end
                    end)
                    return
                end
                local decOk, data = pcall(function() return HttpService:JSONDecode(body) end)
                if not decOk or not data or type(data.collection) ~= "table" then
                    loadMoreBtn.Text = "⚠ No more results"
                    loadMoreBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
                    return
                end
                local newResults = {}
                for _, scTrack in ipairs(data.collection) do
                    if scTrack.kind == "track" then
                        local hqThumb = scTrack.artwork_url
                        if hqThumb then hqThumb = hqThumb:gsub("-large%.jpg", "-t500x500.jpg") end
                        table.insert(newResults, {
                            title    = scTrack.title,
                            duration = scTrack.duration and math.floor(scTrack.duration / 1000) or 0,
                            thumbnail = hqThumb,
                            sc_track  = scTrack
                        })
                    end
                end
                if #newResults == 0 then
                    loadMoreBtn.Text = "✓ No more results"
                    loadMoreBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
                    return
                end
                musicCurrentOffset = nextOffset
                for _, t in ipairs(newResults) do table.insert(musicCurrentResults, t) end
                musicShowResults(newResults, true)
            end)
        end)
    end

    -- Back button: return to results without stopping audio
    MusicBackBtn.MouseButton1Click:Connect(function()
        if #musicCurrentResults == 0 then return end
        MusicThumbnail.Visible = false
        MusicResultsPanel.Visible = true
    end)

    MusicSearchBtn.MouseButton1Click:Connect(function()
        local query = MusicSearchBox.Text
        if not query or query:match("^%s*$") then return end
        musicCurrentQuery  = query
        musicCurrentOffset = 0
        MusicResultsPanel.Visible = false
        MusicThumbnail.Visible = false
        MusicBackBtn.Visible = false
        MusicSearchBtn.Text             = "Searching..."
        MusicSearchBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)

        task.spawn(function()
            local searchUrl = "https://api-v2.soundcloud.com/search/tracks?q="
                .. HttpService:UrlEncode(query)
                .. "&client_id=" .. MUSIC_SC_CLIENT_ID
                .. "&limit=20&offset=0"
            local body = musicSafeGet(searchUrl)
            if not body then
                MusicSearchBtn.Text             = "Net Error"
                MusicSearchBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
                task.delay(2, function()
                    MusicSearchBtn.Text             = "🔍 Search"
                    MusicSearchBtn.BackgroundColor3 = Color3.fromRGB(255, 85, 0)
                end)
                return
            end
            local decOk, data = pcall(function() return HttpService:JSONDecode(body) end)
            if not decOk or not data or type(data.collection) ~= "table" then
                MusicSearchBtn.Text             = "Bad Data"
                MusicSearchBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
                task.delay(2, function()
                    MusicSearchBtn.Text             = "🔍 Search"
                    MusicSearchBtn.BackgroundColor3 = Color3.fromRGB(255, 85, 0)
                end)
                return
            end
            local results = {}
            for _, scTrack in ipairs(data.collection) do
                if scTrack.kind == "track" then
                    -- Grab HQ thumbnail URL from artwork_url
                    local hqThumb = scTrack.artwork_url
                    if hqThumb then
                        hqThumb = hqThumb:gsub("-large%.jpg", "-t500x500.jpg")
                    end
                    table.insert(results, {
                        title     = scTrack.title,
                        duration  = scTrack.duration and math.floor(scTrack.duration / 1000) or 0,
                        thumbnail = hqThumb,
                        sc_track  = scTrack
                    })
                end
            end
            if #results == 0 then
                MusicSearchBtn.Text             = "No Results"
                MusicSearchBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
                task.delay(2, function()
                    MusicSearchBtn.Text             = "🔍 Search"
                    MusicSearchBtn.BackgroundColor3 = Color3.fromRGB(255, 85, 0)
                end)
                return
            end
            musicCurrentResults = results
            musicCurrentIndex   = 0
            musicCurrentOffset  = 0
            musicShowResults(results, false)
            MusicSearchBtn.Text             = "✓ " .. #results .. " found"
            MusicSearchBtn.BackgroundColor3 = Color3.fromRGB(30, 140, 60)
            task.delay(1.5, function()
                MusicSearchBtn.Text             = "🔍 Search"
                MusicSearchBtn.BackgroundColor3 = Color3.fromRGB(255, 85, 0)
            end)
        end)
    end)

    MusicPlayBtn.MouseButton1Click:Connect(function()
        if musicIsPaused then
            local ap = getMusicAudioPlayer()
            pcall(function() ap:Resume() end)
            musicSetPlayState("playing")
            musicStartProgressLoop()
            -- Re-broadcast so late-joining listeners catch it
            if musicCurrentTrack then
                task.spawn(function()
                    musicBroadcastPlay(musicLastBroadcastUrl, musicCurrentTrack.title or "Unknown")
                end)
            end
            return
        end
        if musicIsPlaying then
            local ap = getMusicAudioPlayer()
            pcall(function() ap:Pause() end)
            musicStopProgressLoop()
            musicSetPlayState("paused")
            return
        end
        if musicIsBusy then return end
        if not musicCurrentTrack then
            if MusicPlayBtn and MusicPlayBtn.Parent then
                MusicPlayBtn.Text = "Pick a song first!"
                task.delay(1.5, function() musicSetPlayState("idle") end)
            end
            return
        end
        musicTrackToken = musicTrackToken + 1
        musicPlayCurrentTrack()
    end)

    MusicStopBtn.MouseButton1Click:Connect(function()
        musicTrackToken = musicTrackToken + 1
        musicStopProgressLoop()
        if musicEndedConn then
            pcall(function() musicEndedConn:Disconnect() end)
            musicEndedConn = nil
        end
        local ap = getMusicAudioPlayer()
        pcall(function() ap:Stop() end)
        pcall(function() ap.SoundId = "" end)
        musicSetPlayState("idle")
        musicSetProgressVisible(false)
        musicResetProgress()
        musicBroadcastStop()
        if MusicSongTitle and MusicSongTitle.Parent then
            MusicSongTitle.Text = "No song selected"
        end
        if MusicSongDuration and MusicSongDuration.Parent then
            MusicSongDuration.Text = "Duration: 0:00"
        end
        if MusicThumbnail and MusicThumbnail.Parent then
            MusicThumbnail.Visible = false
            MusicThumbnail.Image = ""
        end
        MusicBackBtn.Visible = false
    end)

    MusicPrevBtn.MouseButton1Click:Connect(function()
        if #musicCurrentResults == 0 then return end
        musicTrackToken = musicTrackToken + 1
        if musicShuffleOn and #musicCurrentResults > 1 then
            local newIdx
            repeat newIdx = math.random(1, #musicCurrentResults) until newIdx ~= musicCurrentIndex
            musicCurrentIndex = newIdx
        else
            musicCurrentIndex = musicCurrentIndex - 1
            if musicCurrentIndex < 1 then musicCurrentIndex = #musicCurrentResults end
        end
        musicPopulateTrackInfo(musicCurrentResults[musicCurrentIndex])
        musicPlayCurrentTrack()
    end)

    MusicNextBtn.MouseButton1Click:Connect(function()
        if #musicCurrentResults == 0 then return end
        musicTrackToken = musicTrackToken + 1
        if musicShuffleOn and #musicCurrentResults > 1 then
            local newIdx
            repeat newIdx = math.random(1, #musicCurrentResults) until newIdx ~= musicCurrentIndex
            musicCurrentIndex = newIdx
        else
            musicCurrentIndex = musicCurrentIndex + 1
            if musicCurrentIndex > #musicCurrentResults then musicCurrentIndex = 1 end
        end
        musicPopulateTrackInfo(musicCurrentResults[musicCurrentIndex])
        musicPlayCurrentTrack()
    end)

    -- Shuffle toggle
    MusicShuffleBtn.MouseButton1Click:Connect(function()
        musicShuffleOn = not musicShuffleOn
        if musicShuffleOn then
            MusicShuffleBtn.BackgroundColor3 = Color3.fromRGB(255, 85, 0)
            MusicShuffleBtn.TextColor3       = Color3.new(1, 1, 1)
        else
            MusicShuffleBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
            MusicShuffleBtn.TextColor3       = Color3.fromRGB(160, 160, 160)
        end
    end)

    -- Loop toggle
    MusicLoopBtn.MouseButton1Click:Connect(function()
        musicLoopOn = not musicLoopOn
        if musicLoopOn then
            MusicLoopBtn.BackgroundColor3 = Color3.fromRGB(255, 85, 0)
            MusicLoopBtn.TextColor3       = Color3.new(1, 1, 1)
        else
            MusicLoopBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
            MusicLoopBtn.TextColor3       = Color3.fromRGB(160, 160, 160)
        end
    end)

    -- Volume cycling (click the NowPlaying label to cycle volume)
    MusicNowPlayingLabel.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            musicVolIdx = (musicVolIdx % #musicVolLevels) + 1
            local ap = getMusicAudioPlayer()
            ap.Volume = musicVolLevels[musicVolIdx]
            if MusicVolLabel and MusicVolLabel.Parent then
                MusicVolLabel.Text = "Vol: " .. tostring(math.floor(musicVolLevels[musicVolIdx] * 100)) .. "%"
            end
        end
    end)

    -- ── Seekable progress bar (click or drag) ──────────────────
    local function musicSeekToX(inputX)
        local ap = getMusicAudioPlayer()
        local len = ap.TimeLength
        if not len or len <= 0 then return end
        if not musicIsPlaying and not musicIsPaused then return end
        local barX  = MusicProgressBG.AbsolutePosition.X
        local barW  = MusicProgressBG.AbsoluteSize.X
        local ratio = math.clamp((inputX - barX) / barW, 0, 1)
        ap.TimePosition = ratio * len
        if MusicProgressFill and MusicProgressFill.Parent then
            MusicProgressFill.Size = UDim2.new(ratio, 0, 1, 0)
        end
        if MusicSeekKnob and MusicSeekKnob.Parent then
            MusicSeekKnob.Position = UDim2.new(ratio, 0, 0.5, 0)
        end
        if MusicTimeLeft and MusicTimeLeft.Parent then
            MusicTimeLeft.Text = musicFormatTime(ratio * len)
        end
    end

    MusicProgressBG.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            musicIsSeeking = true
            musicSeekToX(input.Position.X)
        end
    end)

    MusicProgressBG.InputChanged:Connect(function(input)
        if musicIsSeeking and (
            input.UserInputType == Enum.UserInputType.MouseMovement or
            input.UserInputType == Enum.UserInputType.Touch
        ) then
            musicSeekToX(input.Position.X)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            musicIsSeeking = false
        end
    end)

    -- Search on Enter key in music search box
    MusicSearchBox.FocusLost:Connect(function(enter)
        if enter then MusicSearchBtn.MouseButton1Click:Fire() end
    end)
end

-- ============================================================
-- MUSIC LISTENER LOOP — runs for ALL non-creator users.
-- Polls Firebase every 2 seconds. When Creator plays a song,
-- this loop downloads + plays it locally on each client.
-- When Creator stops, this loop stops local playback too.
-- ============================================================
local _musicListenerLastData = ""
local _musicListenerAP       = nil

local function getMusicListenerPlayer()
    if not _musicListenerAP or not _musicListenerAP.Parent then
        _musicListenerAP = Instance.new("Sound")
        _musicListenerAP.Parent = game:GetService("SoundService")
        _musicListenerAP.Volume = 1
        _musicListenerAP.Name   = "AresMusicListener"
    end
    return _musicListenerAP
end

task.spawn(function()
    -- Stagger listener startup slightly
    task.wait(3)
    while true do
        task.wait(2)
        pcall(function()
            local req = syn and syn.request or http and http.request or request
            if not req then return end
            local res = req({ Url = MUSIC_SYNC_URL .. "/" .. JobId .. ".json", Method = "GET" })
            if not res or not res.Success then return end

            local body = res.Body
            if body == "null" or body == "" then
                -- Creator stopped — stop listener playback
                if _musicListenerLastData ~= "null" and _musicListenerLastData ~= "" then
                    _musicListenerLastData = "null"
                    if RealUserId ~= CREATOR_ID then
                        pcall(function()
                            local ap = getMusicListenerPlayer()
                            ap:Stop()
                            ap.SoundId = ""
                        end)
                    end
                end
                return
            end

            if body == _musicListenerLastData then return end
            _musicListenerLastData = body

            -- Don't run listener logic for the Creator (they play locally already)
            if RealUserId == CREATOR_ID then return end

            local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
            if not ok or type(data) ~= "table" then return end
            if data.Action ~= "play" then return end

            local streamUrl = data.StreamUrl
            local title     = data.Title or "Unknown"
            if not streamUrl or streamUrl == "" then return end

            -- Download and play
            task.spawn(function()
                pcall(function() makefolder("ares music") end)
                local ap = getMusicListenerPlayer()
                ap:Stop()
                ap.SoundId = ""

                -- Try to download locally first
                local audioAsset
                pcall(function()
                    local body2 = musicSafeGet(streamUrl)
                    if body2 and #body2 > 0 then
                        local wOk = pcall(writefile, "ares music/music_listener.mp3", body2)
                        if wOk then
                            task.wait(0.08)
                            pcall(function() audioAsset = getcustomasset("ares music/music_listener.mp3") end)
                        end
                    end
                end)

                local setOk = false
                if audioAsset then
                    setOk = pcall(function() ap.SoundId = audioAsset end)
                end
                if not setOk then
                    pcall(function() ap.SoundId = streamUrl end)
                end

                pcall(function() ap.TimePosition = 0 end)
                pcall(function() ap:Play() end)
            end)
        end)
    end
end)

-- ============================================================
-- BACKGROUND LOOPS
-- ============================================================

-- Main sync loop — 0.5 s interval for near-instant message delivery
task.spawn(function() while task.wait(0.5) do sync() end end)

-- ============================================================
-- INSTANT UNSEND SYNC LOOP — polls /unsent every 0.5 seconds.
-- When any client unsends a message, its Firebase key is written
-- to UNSENT_URL.  All other clients detect it here and instantly
-- destroy the matching UI frame.
-- ============================================================
local lastUnsentData = ""
task.spawn(function()
    while task.wait(0.5) do
        pcall(function()
            local req = syn and syn.request or http and http.request or request
            if not req then return end
            local res = req({Url = UNSENT_URL .. ".json", Method = "GET"})
            if not res.Success or res.Body == "null" or res.Body == lastUnsentData then return end
            lastUnsentData = res.Body
            local ok, unsentData = pcall(HttpService.JSONDecode, HttpService, res.Body)
            if not ok or type(unsentData) ~= "table" then return end
            for fbKey, _ in pairs(unsentData) do
                local btn = keyToButton[fbKey]
                if btn then
                    local wf = btn and btn.Parent
                    keyToButton[fbKey] = nil
                    SpecialLabels[btn] = nil
                    NormalTitleLabels[btn] = nil
                    local newKeys = {}
                    for _, sk in ipairs(sortedMessageKeys) do
                        if sk ~= fbKey then table.insert(newKeys, sk) end
                    end
                    sortedMessageKeys = newKeys
                    if wf and wf.Parent then
                        TweenService:Create(btn,
                            TweenInfo.new(0.15, Enum.EasingStyle.Quad),
                            {BackgroundTransparency = 1}):Play()
                        task.delay(0.16, function()
                            if wf and wf.Parent then wf:Destroy() end
                        end)
                    end
                end
            end
        end)
    end
end)


-- CUSTOM TITLES SYNC LOOP — sync every 10 seconds so all clients
-- see title/untitle updates instantly without rejoining.
task.spawn(function()
    while task.wait(10) do
        syncCustomTitles()
    end
end)

-- IDLE AUTO-CLEAR LOOP
-- If no message activity for 10 minutes, silently wipe UI + Firebase.
-- lastMessageTime is updated on every real message sent OR received.
task.spawn(function()
    while task.wait(30) do  -- check every 30 seconds
        local elapsed = os.time() - lastMessageTime
        if elapsed >= IDLE_CLEAR_SECONDS then
            -- Check if there is actually anything to clear
            local hasMessages = false
            for _, child in pairs(ChatLog:GetChildren()) do
                if child:IsA("Frame") then hasMessages = true break end  -- wrapperFrames
            end
            if hasMessages then
                -- Wipe local UI
                for _, child in pairs(ChatLog:GetChildren()) do
                    if child:IsA("Frame") then child:Destroy() end  -- wrapperFrames
                end
                sortedMessageKeys = {}
                keyToButton = {}
                -- Wipe Firebase database
                local req = syn and syn.request or http and http.request or request
                if req then
                    pcall(function()
                        req({Url = DATABASE_URL .. ".json", Method = "DELETE"})
                    end)
                end
                processedKeys = {}
                lastData = ""
                -- Reset idle timer so it doesn't keep firing
                lastMessageTime = os.time()
            end
        end
    end
end)