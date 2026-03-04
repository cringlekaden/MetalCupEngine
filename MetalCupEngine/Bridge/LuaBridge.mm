// LuaBridge.mm
// Lua scripting bridge for MetalCupEngine.

#import <Foundation/Foundation.h>

#include <algorithm>
#include <cctype>
#include <cstring>
#include <mutex>
#include <set>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

extern "C" {
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
}

namespace {
    using LuaLogCallback = void (*)(void *hostContext, int32_t level, const char *message);
    using LuaEntityExistsCallback = uint32_t (*)(void *hostContext, const char *entityId);
    using LuaEntityGetNameCallback = uint32_t (*)(void *hostContext, const char *entityId, char *buffer, int32_t bufferSize);
    using LuaEntityGetTransformCallback = uint32_t (*)(void *hostContext, const char *entityId, float *positionOut, float *rotationEulerOut, float *scaleOut);
    using LuaEntitySetTransformCallback = uint32_t (*)(void *hostContext, const char *entityId, const float *position, const float *rotationEuler, const float *scale);
    using LuaEntityMoveCallback = void (*)(void *hostContext, const char *entityId, float x, float y, float z);
    using LuaEntitySetMoveInputCallback = void (*)(void *hostContext, const char *entityId, float x, float z);
    using LuaEntitySetLookInputCallback = void (*)(void *hostContext, const char *entityId, float deltaX, float deltaY);
    using LuaEntitySetSprintCallback = void (*)(void *hostContext, const char *entityId, uint32_t enabled);
    using LuaEntityJumpCallback = void (*)(void *hostContext, const char *entityId);
    using LuaEntityIsGroundedCallback = uint32_t (*)(void *hostContext, const char *entityId);
    using LuaEntityGetVelocityCallback = uint32_t (*)(void *hostContext, const char *entityId, float *velocityOut);
    using LuaInputIsKeyDownCallback = uint32_t (*)(void *hostContext, uint16_t keyCode);
    using LuaInputWasKeyPressedCallback = uint32_t (*)(void *hostContext, uint16_t keyCode);
    using LuaInputGetMouseDeltaCallback = uint32_t (*)(void *hostContext, float *deltaOut);
    using LuaInputSetCursorModeCallback = void (*)(void *hostContext, int32_t mode);
    using LuaInputGetCursorModeCallback = int32_t (*)(void *hostContext);
    using LuaInputToggleCursorModeLockedCallback = void (*)(void *hostContext);
    using LuaAssetGetNameCallback = uint32_t (*)(void *hostContext, const char *assetHandle, char *buffer, int32_t bufferSize);

    static constexpr int kEntityIdBufferSize = 64;

    struct LuaScriptHost;

    struct LuaScriptInstance {
        std::string scriptPath;
        int selfRef = LUA_NOREF;
        int onCreateRef = LUA_NOREF;
        int onStartRef = LUA_NOREF;
        int onUpdateRef = LUA_NOREF;
        int onFixedUpdateRef = LUA_NOREF;
        int onDestroyRef = LUA_NOREF;
        bool faulted = false;
        std::string lastError;
    };

    struct LuaScriptHost {
        void *hostContext = nullptr;
        LuaLogCallback logCallback = nullptr;
        LuaEntityExistsCallback entityExistsCallback = nullptr;
        LuaEntityGetNameCallback entityGetNameCallback = nullptr;
        LuaEntityGetTransformCallback entityGetTransformCallback = nullptr;
        LuaEntitySetTransformCallback entitySetTransformCallback = nullptr;
        LuaEntityMoveCallback entityMoveCallback = nullptr;
        LuaEntitySetMoveInputCallback entitySetMoveInputCallback = nullptr;
        LuaEntitySetLookInputCallback entitySetLookInputCallback = nullptr;
        LuaEntitySetSprintCallback entitySetSprintCallback = nullptr;
        LuaEntityJumpCallback entityJumpCallback = nullptr;
        LuaEntityIsGroundedCallback entityIsGroundedCallback = nullptr;
        LuaEntityGetVelocityCallback entityGetVelocityCallback = nullptr;
        LuaInputIsKeyDownCallback inputIsKeyDownCallback = nullptr;
        LuaInputWasKeyPressedCallback inputWasKeyPressedCallback = nullptr;
        LuaInputGetMouseDeltaCallback inputGetMouseDeltaCallback = nullptr;
        LuaInputSetCursorModeCallback inputSetCursorModeCallback = nullptr;
        LuaInputGetCursorModeCallback inputGetCursorModeCallback = nullptr;
        LuaInputToggleCursorModeLockedCallback inputToggleCursorModeLockedCallback = nullptr;
        LuaAssetGetNameCallback assetGetNameCallback = nullptr;
        lua_State *L = nullptr;
        std::unordered_map<std::string, LuaScriptInstance> instances;
    };

    static void WriteCString(const std::string &text, char *buffer, int32_t size) {
        if (!buffer || size <= 0) { return; }
        const int32_t maxCount = size - 1;
        const int32_t count = std::min<int32_t>(maxCount, static_cast<int32_t>(text.size()));
        if (count > 0) {
            memcpy(buffer, text.data(), static_cast<size_t>(count));
        }
        buffer[count] = 0;
    }

    static void UnrefIfValid(lua_State *L, int &ref) {
        if (!L || ref == LUA_NOREF) { return; }
        luaL_unref(L, LUA_REGISTRYINDEX, ref);
        ref = LUA_NOREF;
    }

    static void ClearInstanceRefs(lua_State *L, LuaScriptInstance &instance) {
        UnrefIfValid(L, instance.selfRef);
        UnrefIfValid(L, instance.onCreateRef);
        UnrefIfValid(L, instance.onStartRef);
        UnrefIfValid(L, instance.onUpdateRef);
        UnrefIfValid(L, instance.onFixedUpdateRef);
        UnrefIfValid(L, instance.onDestroyRef);
    }

    static void LogMessage(LuaScriptHost *host, int32_t level, const std::string &text) {
        if (!host || !host->logCallback) { return; }
        host->logCallback(host->hostContext, level, text.c_str());
    }

    static void LogInfo(LuaScriptHost *host, const std::string &text) { LogMessage(host, 0, text); }
    static void LogWarning(LuaScriptHost *host, const std::string &text) { LogMessage(host, 1, text); }
    static void LogError(LuaScriptHost *host, const std::string &text) { LogMessage(host, 2, text); }

    static std::string FormatLuaError(const std::string &entityId,
                                      const std::string &scriptPath,
                                      const std::string &phase,
                                      const std::string &details) {
        std::ostringstream stream;
        stream << phase << " failed for entity " << entityId << " (" << scriptPath << "): " << details;
        return stream.str();
    }

    static bool ReadVec3FromLuaTable(lua_State *L, int index, float outVec[3], const float fallback[3]) {
        if (!lua_istable(L, index)) { return false; }
        outVec[0] = fallback[0];
        outVec[1] = fallback[1];
        outVec[2] = fallback[2];

        lua_rawgeti(L, index, 1);
        if (lua_isnumber(L, -1)) { outVec[0] = static_cast<float>(lua_tonumber(L, -1)); }
        lua_pop(L, 1);
        lua_rawgeti(L, index, 2);
        if (lua_isnumber(L, -1)) { outVec[1] = static_cast<float>(lua_tonumber(L, -1)); }
        lua_pop(L, 1);
        lua_rawgeti(L, index, 3);
        if (lua_isnumber(L, -1)) { outVec[2] = static_cast<float>(lua_tonumber(L, -1)); }
        lua_pop(L, 1);

        // Prefer named fields over array slots so scripts that mutate p.x/p.y/p.z
        // are not overwritten by stale [1]/[2]/[3] values.
        lua_getfield(L, index, "x");
        if (lua_isnumber(L, -1)) { outVec[0] = static_cast<float>(lua_tonumber(L, -1)); }
        lua_pop(L, 1);
        lua_getfield(L, index, "y");
        if (lua_isnumber(L, -1)) { outVec[1] = static_cast<float>(lua_tonumber(L, -1)); }
        lua_pop(L, 1);
        lua_getfield(L, index, "z");
        if (lua_isnumber(L, -1)) { outVec[2] = static_cast<float>(lua_tonumber(L, -1)); }
        lua_pop(L, 1);
        return true;
    }

    static void PushVec3Table(lua_State *L, const float vec[3]) {
        lua_createtable(L, 3, 3);
        lua_pushnumber(L, vec[0]); lua_setfield(L, -2, "x");
        lua_pushnumber(L, vec[1]); lua_setfield(L, -2, "y");
        lua_pushnumber(L, vec[2]); lua_setfield(L, -2, "z");
        lua_pushnumber(L, vec[0]); lua_rawseti(L, -2, 1);
        lua_pushnumber(L, vec[1]); lua_rawseti(L, -2, 2);
        lua_pushnumber(L, vec[2]); lua_rawseti(L, -2, 3);
    }

    static void PushVec2Table(lua_State *L, float x, float y) {
        lua_createtable(L, 2, 2);
        lua_pushnumber(L, x); lua_setfield(L, -2, "x");
        lua_pushnumber(L, y); lua_setfield(L, -2, "y");
        lua_pushnumber(L, x); lua_rawseti(L, -2, 1);
        lua_pushnumber(L, y); lua_rawseti(L, -2, 2);
    }

    static LuaScriptHost *BoundHostOrNil(lua_State *L) {
        LuaScriptHost *host = static_cast<LuaScriptHost *>(lua_touserdata(L, lua_upvalueindex(1)));
        if (!host) { return nullptr; }
        if (!host->entityExistsCallback) { return nullptr; }
        const char *entityId = lua_tostring(L, lua_upvalueindex(2));
        if (!entityId || host->entityExistsCallback(host->hostContext, entityId) == 0) {
            if (entityId) {
                LogWarning(host, std::string("Lua entity binding lost target entity: ") + entityId);
            } else {
                LogWarning(host, "Lua entity binding missing entity id.");
            }
            return nullptr;
        }
        return host;
    }

    static const char *BoundEntityId(lua_State *L) {
        const char *entityId = lua_tostring(L, lua_upvalueindex(2));
        return entityId ? entityId : "";
    }

    static const char *BoundAssetHandle(lua_State *L) {
        const char *handle = lua_tostring(L, lua_upvalueindex(2));
        return handle ? handle : "";
    }

    static int VecInputArgIndex(lua_State *L) {
        if (lua_istable(L, 2)) { return 2; }
        if (lua_istable(L, 1)) { return 1; }
        return 0;
    }

    static int LuaEntityGetName(lua_State *L) {
        LuaScriptHost *host = BoundHostOrNil(L);
        if (!host || !host->entityGetNameCallback) {
            lua_pushliteral(L, "");
            return 1;
        }
        char nameBuffer[512] = {0};
        if (host->entityGetNameCallback(host->hostContext, BoundEntityId(L), nameBuffer, static_cast<int32_t>(sizeof(nameBuffer))) == 0) {
            lua_pushliteral(L, "");
            return 1;
        }
        lua_pushstring(L, nameBuffer);
        return 1;
    }

    static int LuaEntityGetID(lua_State *L) {
        lua_pushstring(L, BoundEntityId(L));
        return 1;
    }

    static int LuaEntityGetPosition(lua_State *L) {
        LuaScriptHost *host = BoundHostOrNil(L);
        float position[3] = {0, 0, 0};
        float rotation[3] = {0, 0, 0};
        float scale[3] = {1, 1, 1};
        if (host && host->entityGetTransformCallback) {
            host->entityGetTransformCallback(host->hostContext, BoundEntityId(L), position, rotation, scale);
        }
        PushVec3Table(L, position);
        return 1;
    }

    static int LuaEntityGetRotationEuler(lua_State *L) {
        LuaScriptHost *host = BoundHostOrNil(L);
        float position[3] = {0, 0, 0};
        float rotation[3] = {0, 0, 0};
        float scale[3] = {1, 1, 1};
        if (host && host->entityGetTransformCallback) {
            host->entityGetTransformCallback(host->hostContext, BoundEntityId(L), position, rotation, scale);
        }
        PushVec3Table(L, rotation);
        return 1;
    }

    static int LuaEntityGetScale(lua_State *L) {
        LuaScriptHost *host = BoundHostOrNil(L);
        float position[3] = {0, 0, 0};
        float rotation[3] = {0, 0, 0};
        float scale[3] = {1, 1, 1};
        if (host && host->entityGetTransformCallback) {
            host->entityGetTransformCallback(host->hostContext, BoundEntityId(L), position, rotation, scale);
        }
        PushVec3Table(L, scale);
        return 1;
    }

    static int LuaEntitySetPosition(lua_State *L) {
        LuaScriptHost *host = BoundHostOrNil(L);
        if (!host || !host->entityGetTransformCallback || !host->entitySetTransformCallback) {
            if (host) {
                LogWarning(host, std::string("SetPosition unavailable for entity ") + BoundEntityId(L));
            }
            return 0;
        }
        float position[3] = {0, 0, 0};
        float rotation[3] = {0, 0, 0};
        float scale[3] = {1, 1, 1};
        const char *entityId = BoundEntityId(L);
        if (host->entityGetTransformCallback(host->hostContext, entityId, position, rotation, scale) == 0) {
            LogWarning(host, std::string("SetPosition failed to read transform for entity ") + entityId);
            return 0;
        }
        float updated[3] = {position[0], position[1], position[2]};
        const int valueIndex = VecInputArgIndex(L);
        if (valueIndex != 0 && ReadVec3FromLuaTable(L, valueIndex, updated, position)) {
            if (host->entitySetTransformCallback(host->hostContext, entityId, updated, rotation, scale) == 0) {
                LogWarning(host, std::string("SetPosition failed to write transform for entity ") + entityId);
            }
        }
        return 0;
    }

    static int LuaEntitySetRotationEuler(lua_State *L) {
        LuaScriptHost *host = BoundHostOrNil(L);
        if (!host || !host->entityGetTransformCallback || !host->entitySetTransformCallback) {
            if (host) {
                LogWarning(host, std::string("SetRotationEuler unavailable for entity ") + BoundEntityId(L));
            }
            return 0;
        }
        float position[3] = {0, 0, 0};
        float rotation[3] = {0, 0, 0};
        float scale[3] = {1, 1, 1};
        const char *entityId = BoundEntityId(L);
        if (host->entityGetTransformCallback(host->hostContext, entityId, position, rotation, scale) == 0) {
            LogWarning(host, std::string("SetRotationEuler failed to read transform for entity ") + entityId);
            return 0;
        }
        float updated[3] = {rotation[0], rotation[1], rotation[2]};
        const int valueIndex = VecInputArgIndex(L);
        if (valueIndex != 0 && ReadVec3FromLuaTable(L, valueIndex, updated, rotation)) {
            if (host->entitySetTransformCallback(host->hostContext, entityId, position, updated, scale) == 0) {
                LogWarning(host, std::string("SetRotationEuler failed to write transform for entity ") + entityId);
            }
        }
        return 0;
    }

    static int LuaEntitySetScale(lua_State *L) {
        LuaScriptHost *host = BoundHostOrNil(L);
        if (!host || !host->entityGetTransformCallback || !host->entitySetTransformCallback) {
            if (host) {
                LogWarning(host, std::string("SetScale unavailable for entity ") + BoundEntityId(L));
            }
            return 0;
        }
        float position[3] = {0, 0, 0};
        float rotation[3] = {0, 0, 0};
        float scale[3] = {1, 1, 1};
        const char *entityId = BoundEntityId(L);
        if (host->entityGetTransformCallback(host->hostContext, entityId, position, rotation, scale) == 0) {
            LogWarning(host, std::string("SetScale failed to read transform for entity ") + entityId);
            return 0;
        }
        float updated[3] = {scale[0], scale[1], scale[2]};
        const int valueIndex = VecInputArgIndex(L);
        if (valueIndex != 0 && ReadVec3FromLuaTable(L, valueIndex, updated, scale)) {
            if (host->entitySetTransformCallback(host->hostContext, entityId, position, rotation, updated) == 0) {
                LogWarning(host, std::string("SetScale failed to write transform for entity ") + entityId);
            }
        }
        return 0;
    }

    static int LuaEntityMove(lua_State *L) {
        LuaScriptHost *host = BoundHostOrNil(L);
        if (!host || !host->entityMoveCallback) { return 0; }
        const int valueIndex = VecInputArgIndex(L);
        if (valueIndex == 0) { return 0; }
        float direction[3] = {0, 0, 0};
        const float fallback[3] = {0, 0, 0};
        if (ReadVec3FromLuaTable(L, valueIndex, direction, fallback)) {
            host->entityMoveCallback(host->hostContext, BoundEntityId(L), direction[0], direction[1], direction[2]);
        }
        return 0;
    }

    static int LuaEntityJump(lua_State *L) {
        LuaScriptHost *host = BoundHostOrNil(L);
        if (!host || !host->entityJumpCallback) { return 0; }
        host->entityJumpCallback(host->hostContext, BoundEntityId(L));
        return 0;
    }

    static int LuaEntityIsGrounded(lua_State *L) {
        LuaScriptHost *host = BoundHostOrNil(L);
        if (!host || !host->entityIsGroundedCallback) {
            lua_pushboolean(L, 0);
            return 1;
        }
        const uint32_t grounded = host->entityIsGroundedCallback(host->hostContext, BoundEntityId(L));
        lua_pushboolean(L, grounded != 0 ? 1 : 0);
        return 1;
    }

    static int LuaEntitySetMoveInput(lua_State *L) {
        LuaScriptHost *host = BoundHostOrNil(L);
        if (!host || !host->entitySetMoveInputCallback) { return 0; }
        int first = 1;
        if (lua_istable(L, 1)) {
            first = 2;
        }
        float x = static_cast<float>(luaL_optnumber(L, first, 0.0));
        float z = static_cast<float>(luaL_optnumber(L, first + 1, 0.0));
        host->entitySetMoveInputCallback(host->hostContext, BoundEntityId(L), x, z);
        return 0;
    }

    static int LuaEntitySetLookInput(lua_State *L) {
        LuaScriptHost *host = BoundHostOrNil(L);
        if (!host || !host->entitySetLookInputCallback) { return 0; }
        int first = 1;
        if (lua_istable(L, 1)) {
            first = 2;
        }
        float deltaX = static_cast<float>(luaL_optnumber(L, first, 0.0));
        float deltaY = static_cast<float>(luaL_optnumber(L, first + 1, 0.0));
        host->entitySetLookInputCallback(host->hostContext, BoundEntityId(L), deltaX, deltaY);
        return 0;
    }

    static int LuaEntitySetSprint(lua_State *L) {
        LuaScriptHost *host = BoundHostOrNil(L);
        if (!host || !host->entitySetSprintCallback) { return 0; }
        const int argIndex = lua_istable(L, 1) ? 2 : 1;
        const int enabled = lua_toboolean(L, argIndex);
        host->entitySetSprintCallback(host->hostContext, BoundEntityId(L), enabled != 0 ? 1u : 0u);
        return 0;
    }

    static int LuaEntityGetVelocity(lua_State *L) {
        LuaScriptHost *host = BoundHostOrNil(L);
        if (!host || !host->entityGetVelocityCallback) {
            float zero[3] = {0.0f, 0.0f, 0.0f};
            PushVec3Table(L, zero);
            return 1;
        }
        float velocity[3] = {0, 0, 0};
        host->entityGetVelocityCallback(host->hostContext, BoundEntityId(L), velocity);
        PushVec3Table(L, velocity);
        return 1;
    }

    static int LuaInputIsKeyDown(lua_State *L) {
        LuaScriptHost *host = static_cast<LuaScriptHost *>(lua_touserdata(L, lua_upvalueindex(1)));
        if (!host || !host->inputIsKeyDownCallback) {
            lua_pushboolean(L, 0);
            return 1;
        }
        const uint16_t key = static_cast<uint16_t>(luaL_optinteger(L, 1, 0));
        lua_pushboolean(L, host->inputIsKeyDownCallback(host->hostContext, key) != 0 ? 1 : 0);
        return 1;
    }

    static int LuaInputWasKeyPressed(lua_State *L) {
        LuaScriptHost *host = static_cast<LuaScriptHost *>(lua_touserdata(L, lua_upvalueindex(1)));
        if (!host || !host->inputWasKeyPressedCallback) {
            lua_pushboolean(L, 0);
            return 1;
        }
        const uint16_t key = static_cast<uint16_t>(luaL_optinteger(L, 1, 0));
        lua_pushboolean(L, host->inputWasKeyPressedCallback(host->hostContext, key) != 0 ? 1 : 0);
        return 1;
    }

    static int LuaInputGetMouseDelta(lua_State *L) {
        LuaScriptHost *host = static_cast<LuaScriptHost *>(lua_touserdata(L, lua_upvalueindex(1)));
        if (!host || !host->inputGetMouseDeltaCallback) {
            PushVec2Table(L, 0.0f, 0.0f);
            return 1;
        }
        float delta[2] = {0.0f, 0.0f};
        host->inputGetMouseDeltaCallback(host->hostContext, delta);
        PushVec2Table(L, delta[0], delta[1]);
        return 1;
    }

    static int LuaInputSetCursorMode(lua_State *L) {
        LuaScriptHost *host = static_cast<LuaScriptHost *>(lua_touserdata(L, lua_upvalueindex(1)));
        if (!host || !host->inputSetCursorModeCallback) { return 0; }
        const char *mode = luaL_optstring(L, 1, "Normal");
        const int32_t value = (strcmp(mode, "Locked") == 0) ? 1 : 0;
        host->inputSetCursorModeCallback(host->hostContext, value);
        return 0;
    }

    static int LuaInputGetCursorMode(lua_State *L) {
        LuaScriptHost *host = static_cast<LuaScriptHost *>(lua_touserdata(L, lua_upvalueindex(1)));
        if (!host || !host->inputGetCursorModeCallback) {
            lua_pushstring(L, "Normal");
            return 1;
        }
        const int32_t mode = host->inputGetCursorModeCallback(host->hostContext);
        lua_pushstring(L, mode == 1 ? "Locked" : "Normal");
        return 1;
    }

    static int LuaInputToggleCursorModeLocked(lua_State *L) {
        LuaScriptHost *host = static_cast<LuaScriptHost *>(lua_touserdata(L, lua_upvalueindex(1)));
        if (!host || !host->inputToggleCursorModeLockedCallback) { return 0; }
        host->inputToggleCursorModeLockedCallback(host->hostContext);
        return 0;
    }

    static int LuaEntityGetCharacterController(lua_State *L) {
        LuaScriptHost *host = BoundHostOrNil(L);
        if (!host) {
            lua_pushnil(L);
            return 1;
        }
        const char *entityId = BoundEntityId(L);
        lua_createtable(L, 0, 6);
        lua_pushlightuserdata(L, host); lua_pushstring(L, entityId); lua_pushcclosure(L, LuaEntitySetMoveInput, 2); lua_setfield(L, -2, "SetMoveInput");
        lua_pushlightuserdata(L, host); lua_pushstring(L, entityId); lua_pushcclosure(L, LuaEntitySetLookInput, 2); lua_setfield(L, -2, "SetLookInput");
        lua_pushlightuserdata(L, host); lua_pushstring(L, entityId); lua_pushcclosure(L, LuaEntitySetSprint, 2); lua_setfield(L, -2, "SetSprint");
        lua_pushlightuserdata(L, host); lua_pushstring(L, entityId); lua_pushcclosure(L, LuaEntityJump, 2); lua_setfield(L, -2, "Jump");
        lua_pushlightuserdata(L, host); lua_pushstring(L, entityId); lua_pushcclosure(L, LuaEntityIsGrounded, 2); lua_setfield(L, -2, "IsGrounded");
        lua_pushlightuserdata(L, host); lua_pushstring(L, entityId); lua_pushcclosure(L, LuaEntityGetVelocity, 2); lua_setfield(L, -2, "GetVelocity");
        return 1;
    }

    static int LuaEntityRefIsValid(lua_State *L) {
        LuaScriptHost *host = static_cast<LuaScriptHost *>(lua_touserdata(L, lua_upvalueindex(1)));
        if (!host || !host->entityExistsCallback) {
            lua_pushboolean(L, 0);
            return 1;
        }
        lua_pushboolean(L, host->entityExistsCallback(host->hostContext, BoundEntityId(L)) != 0 ? 1 : 0);
        return 1;
    }

    static int LuaEntityRefGetUUID(lua_State *L) {
        lua_pushstring(L, BoundEntityId(L));
        return 1;
    }

    static int LuaEntityRefGetTransform(lua_State *L) {
        LuaScriptHost *host = BoundHostOrNil(L);
        float position[3] = {0, 0, 0};
        float rotation[3] = {0, 0, 0};
        float scale[3] = {1, 1, 1};
        if (host && host->entityGetTransformCallback) {
            host->entityGetTransformCallback(host->hostContext, BoundEntityId(L), position, rotation, scale);
        }
        lua_createtable(L, 0, 3);
        PushVec3Table(L, position);
        lua_setfield(L, -2, "position");
        PushVec3Table(L, rotation);
        lua_setfield(L, -2, "rotation");
        PushVec3Table(L, scale);
        lua_setfield(L, -2, "scale");
        return 1;
    }

    static int LuaEntityRefSetTransform(lua_State *L) {
        LuaScriptHost *host = BoundHostOrNil(L);
        if (!host || !host->entityGetTransformCallback || !host->entitySetTransformCallback) { return 0; }
        if (!lua_istable(L, 1) && !lua_istable(L, 2)) { return 0; }
        const int sourceIndex = lua_istable(L, 2) ? 2 : 1;
        float position[3] = {0, 0, 0};
        float rotation[3] = {0, 0, 0};
        float scale[3] = {1, 1, 1};
        const char *entityId = BoundEntityId(L);
        if (host->entityGetTransformCallback(host->hostContext, entityId, position, rotation, scale) == 0) {
            return 0;
        }

        lua_getfield(L, sourceIndex, "position");
        ReadVec3FromLuaTable(L, lua_gettop(L), position, position);
        lua_pop(L, 1);
        lua_getfield(L, sourceIndex, "rotation");
        ReadVec3FromLuaTable(L, lua_gettop(L), rotation, rotation);
        lua_pop(L, 1);
        lua_getfield(L, sourceIndex, "scale");
        ReadVec3FromLuaTable(L, lua_gettop(L), scale, scale);
        lua_pop(L, 1);

        host->entitySetTransformCallback(host->hostContext, entityId, position, rotation, scale);
        return 0;
    }

    static int LuaPrefabRefIsValid(lua_State *L) {
        const char *handle = BoundAssetHandle(L);
        lua_pushboolean(L, handle[0] != 0 ? 1 : 0);
        return 1;
    }

    static int LuaPrefabRefGetUUID(lua_State *L) {
        lua_pushstring(L, BoundAssetHandle(L));
        return 1;
    }

    static int LuaPrefabRefGetName(lua_State *L) {
        LuaScriptHost *host = static_cast<LuaScriptHost *>(lua_touserdata(L, lua_upvalueindex(1)));
        if (!host || !host->assetGetNameCallback) {
            lua_pushstring(L, BoundAssetHandle(L));
            return 1;
        }
        char nameBuffer[512] = {0};
        if (host->assetGetNameCallback(host->hostContext, BoundAssetHandle(L), nameBuffer, static_cast<int32_t>(sizeof(nameBuffer))) == 0) {
            lua_pushstring(L, BoundAssetHandle(L));
            return 1;
        }
        lua_pushstring(L, nameBuffer);
        return 1;
    }

    static void PushEntityRef(lua_State *L, LuaScriptHost *host, const char *entityId, bool includeControllerAPI) {
        lua_createtable(L, 0, includeControllerAPI ? 16 : 12);
        lua_pushlightuserdata(L, host); lua_pushstring(L, entityId); lua_pushcclosure(L, LuaEntityRefIsValid, 2); lua_setfield(L, -2, "IsValid");
        lua_pushlightuserdata(L, host); lua_pushstring(L, entityId); lua_pushcclosure(L, LuaEntityRefGetUUID, 2); lua_setfield(L, -2, "GetUUID");
        lua_pushlightuserdata(L, host); lua_pushstring(L, entityId); lua_pushcclosure(L, LuaEntityGetName, 2); lua_setfield(L, -2, "GetName");
        lua_pushlightuserdata(L, host); lua_pushstring(L, entityId); lua_pushcclosure(L, LuaEntityRefGetTransform, 2); lua_setfield(L, -2, "GetTransform");
        lua_pushlightuserdata(L, host); lua_pushstring(L, entityId); lua_pushcclosure(L, LuaEntityRefSetTransform, 2); lua_setfield(L, -2, "SetTransform");
        lua_pushlightuserdata(L, host); lua_pushstring(L, entityId); lua_pushcclosure(L, LuaEntityGetID, 2); lua_setfield(L, -2, "GetID");
        // Backward-compatible transform API used by existing scripts.
        lua_pushlightuserdata(L, host); lua_pushstring(L, entityId); lua_pushcclosure(L, LuaEntityGetPosition, 2); lua_setfield(L, -2, "GetPosition");
        lua_pushlightuserdata(L, host); lua_pushstring(L, entityId); lua_pushcclosure(L, LuaEntitySetPosition, 2); lua_setfield(L, -2, "SetPosition");
        lua_pushlightuserdata(L, host); lua_pushstring(L, entityId); lua_pushcclosure(L, LuaEntityGetRotationEuler, 2); lua_setfield(L, -2, "GetRotationEuler");
        lua_pushlightuserdata(L, host); lua_pushstring(L, entityId); lua_pushcclosure(L, LuaEntitySetRotationEuler, 2); lua_setfield(L, -2, "SetRotationEuler");
        lua_pushlightuserdata(L, host); lua_pushstring(L, entityId); lua_pushcclosure(L, LuaEntityGetScale, 2); lua_setfield(L, -2, "GetScale");
        lua_pushlightuserdata(L, host); lua_pushstring(L, entityId); lua_pushcclosure(L, LuaEntitySetScale, 2); lua_setfield(L, -2, "SetScale");
        if (includeControllerAPI) {
            lua_pushlightuserdata(L, host); lua_pushstring(L, entityId); lua_pushcclosure(L, LuaEntityGetCharacterController, 2); lua_setfield(L, -2, "GetCharacterController");
            lua_pushlightuserdata(L, host); lua_pushstring(L, entityId); lua_pushcclosure(L, LuaEntityMove, 2); lua_setfield(L, -2, "Move");
            lua_pushlightuserdata(L, host); lua_pushstring(L, entityId); lua_pushcclosure(L, LuaEntitySetLookInput, 2); lua_setfield(L, -2, "SetLookInput");
            lua_pushlightuserdata(L, host); lua_pushstring(L, entityId); lua_pushcclosure(L, LuaEntityJump, 2); lua_setfield(L, -2, "Jump");
            lua_pushlightuserdata(L, host); lua_pushstring(L, entityId); lua_pushcclosure(L, LuaEntityIsGrounded, 2); lua_setfield(L, -2, "IsGrounded");
        }
    }

    static void PushPrefabRef(lua_State *L, LuaScriptHost *host, const char *assetHandle) {
        lua_createtable(L, 0, 3);
        lua_pushlightuserdata(L, host); lua_pushstring(L, assetHandle); lua_pushcclosure(L, LuaPrefabRefIsValid, 2); lua_setfield(L, -2, "IsValid");
        lua_pushlightuserdata(L, host); lua_pushstring(L, assetHandle); lua_pushcclosure(L, LuaPrefabRefGetUUID, 2); lua_setfield(L, -2, "GetUUID");
        lua_pushlightuserdata(L, host); lua_pushstring(L, assetHandle); lua_pushcclosure(L, LuaPrefabRefGetName, 2); lua_setfield(L, -2, "GetName");
    }

    static int LuaPrint(lua_State *L) {
        LuaScriptHost *host = static_cast<LuaScriptHost *>(lua_touserdata(L, lua_upvalueindex(1)));
        if (!host) { return 0; }
        const int top = lua_gettop(L);
        std::ostringstream stream;
        for (int i = 1; i <= top; ++i) {
            if (i > 1) {
                stream << " ";
            }
            size_t length = 0;
            const char *text = luaL_tolstring(L, i, &length);
            if (text) {
                stream.write(text, static_cast<std::streamsize>(length));
            }
            lua_pop(L, 1);
        }
        LogInfo(host, stream.str());
        return 0;
    }

    static int LuaLogInfo(lua_State *L) {
        LuaScriptHost *host = static_cast<LuaScriptHost *>(lua_touserdata(L, lua_upvalueindex(1)));
        if (!host) { return 0; }
        const char *message = luaL_optstring(L, 1, "");
        LogInfo(host, message);
        return 0;
    }

    static int LuaLogWarn(lua_State *L) {
        LuaScriptHost *host = static_cast<LuaScriptHost *>(lua_touserdata(L, lua_upvalueindex(1)));
        if (!host) { return 0; }
        const char *message = luaL_optstring(L, 1, "");
        LogWarning(host, message);
        return 0;
    }

    static int LuaLogError(lua_State *L) {
        LuaScriptHost *host = static_cast<LuaScriptHost *>(lua_touserdata(L, lua_upvalueindex(1)));
        if (!host) { return 0; }
        const char *message = luaL_optstring(L, 1, "");
        LogError(host, message);
        return 0;
    }

    static void RegisterGlobals(LuaScriptHost *host) {
        if (!host || !host->L) { return; }
        lua_State *L = host->L;
        lua_createtable(L, 0, 1);
        lua_pushnumber(L, 0.0);
        lua_setfield(L, -2, "deltaTime");
        lua_setglobal(L, "Time");

        lua_createtable(L, 0, 3);
        lua_pushlightuserdata(L, host);
        lua_pushcclosure(L, LuaLogInfo, 1);
        lua_setfield(L, -2, "Info");
        lua_pushlightuserdata(L, host);
        lua_pushcclosure(L, LuaLogWarn, 1);
        lua_setfield(L, -2, "Warn");
        lua_pushlightuserdata(L, host);
        lua_pushcclosure(L, LuaLogError, 1);
        lua_setfield(L, -2, "Error");
        lua_setglobal(L, "Log");

        lua_pushlightuserdata(L, host);
        lua_pushcclosure(L, LuaPrint, 1);
        lua_setglobal(L, "print");

        lua_createtable(L, 0, 7);
        lua_pushlightuserdata(L, host);
        lua_pushcclosure(L, LuaInputIsKeyDown, 1);
        lua_setfield(L, -2, "IsKeyDown");
        lua_pushlightuserdata(L, host);
        lua_pushcclosure(L, LuaInputWasKeyPressed, 1);
        lua_setfield(L, -2, "WasKeyPressed");
        lua_pushlightuserdata(L, host);
        lua_pushcclosure(L, LuaInputGetMouseDelta, 1);
        lua_setfield(L, -2, "GetMouseDelta");
        lua_pushlightuserdata(L, host);
        lua_pushcclosure(L, LuaInputSetCursorMode, 1);
        lua_setfield(L, -2, "SetCursorMode");
        lua_pushlightuserdata(L, host);
        lua_pushcclosure(L, LuaInputGetCursorMode, 1);
        lua_setfield(L, -2, "GetCursorMode");
        lua_pushlightuserdata(L, host);
        lua_pushcclosure(L, LuaInputToggleCursorModeLocked, 1);
        lua_setfield(L, -2, "ToggleCursorModeLocked");
        lua_setglobal(L, "Input");

        lua_createtable(L, 0, 8);
        lua_pushinteger(L, 0x0D); lua_setfield(L, -2, "W");
        lua_pushinteger(L, 0x00); lua_setfield(L, -2, "A");
        lua_pushinteger(L, 0x01); lua_setfield(L, -2, "S");
        lua_pushinteger(L, 0x02); lua_setfield(L, -2, "D");
        lua_pushinteger(L, 0x31); lua_setfield(L, -2, "Space");
        lua_pushinteger(L, 0x38); lua_setfield(L, -2, "LeftShift");
        lua_pushinteger(L, 0x7B); lua_setfield(L, -2, "LeftArrow");
        lua_pushinteger(L, 0x7C); lua_setfield(L, -2, "RightArrow");
        lua_setglobal(L, "Key");
    }

    static void SetDeltaTime(LuaScriptHost *host, float dt) {
        if (!host || !host->L) { return; }
        lua_getglobal(host->L, "Time");
        if (lua_istable(host->L, -1)) {
            lua_pushnumber(host->L, dt);
            lua_setfield(host->L, -2, "deltaTime");
        }
        lua_pop(host->L, 1);
    }

    static int FunctionRefFromField(lua_State *L, int tableIndex, const char *name) {
        lua_getfield(L, tableIndex, name);
        if (!lua_isfunction(L, -1)) {
            lua_pop(L, 1);
            return LUA_NOREF;
        }
        return luaL_ref(L, LUA_REGISTRYINDEX);
    }

    static bool CallInstanceFunction(LuaScriptHost *host,
                                     const std::string &entityId,
                                     LuaScriptInstance &instance,
                                     int functionRef,
                                     const char *phase,
                                     float dt,
                                     bool passDelta,
                                     std::string &outError) {
        if (!host || !host->L || functionRef == LUA_NOREF || instance.faulted) {
            return true;
        }
        lua_State *L = host->L;
        lua_rawgeti(L, LUA_REGISTRYINDEX, functionRef);
        if (!lua_isfunction(L, -1)) {
            lua_pop(L, 1);
            return true;
        }
        lua_rawgeti(L, LUA_REGISTRYINDEX, instance.selfRef);
        if (passDelta) {
            lua_pushnumber(L, dt);
        }
        const int argCount = passDelta ? 2 : 1;
        if (lua_pcall(L, argCount, 0, 0) == LUA_OK) {
            return true;
        }
        const char *errorText = lua_tostring(L, -1);
        outError = FormatLuaError(entityId, instance.scriptPath, phase, errorText ? errorText : "Unknown Lua error.");
        lua_pop(L, 1);
        instance.lastError = outError;
        instance.faulted = true;
        if (host->inputSetCursorModeCallback) {
            host->inputSetCursorModeCallback(host->hostContext, 0);
        }
        LogError(host, outError);
        return false;
    }

    static bool DestroyInstanceInternal(LuaScriptHost *host, const std::string &entityId, std::string *outError) {
        if (!host || !host->L) { return false; }
        auto it = host->instances.find(entityId);
        if (it == host->instances.end()) { return true; }

        std::string callbackError;
        LuaScriptInstance &instance = it->second;
        if (!instance.faulted) {
            CallInstanceFunction(host, entityId, instance, instance.onDestroyRef, "OnDestroy", 0.0f, false, callbackError);
        }
        ClearInstanceRefs(host->L, instance);
        host->instances.erase(it);
        if (outError && !callbackError.empty()) {
            *outError = callbackError;
        }
        return callbackError.empty();
    }

    static bool InstantiateInternal(LuaScriptHost *host,
                                    const std::string &entityId,
                                    const std::string &scriptPath,
                                    std::string &outError) {
        if (!host || !host->L) { return false; }
        DestroyInstanceInternal(host, entityId, nullptr);
        lua_State *L = host->L;

        if (luaL_loadfile(L, scriptPath.c_str()) != LUA_OK) {
            const char *errorText = lua_tostring(L, -1);
            outError = FormatLuaError(entityId, scriptPath, "Load", errorText ? errorText : "Unable to load file.");
            lua_pop(L, 1);
            LogError(host, outError);
            return false;
        }
        if (lua_pcall(L, 0, 1, 0) != LUA_OK) {
            const char *errorText = lua_tostring(L, -1);
            outError = FormatLuaError(entityId, scriptPath, "Execute", errorText ? errorText : "Unable to execute chunk.");
            lua_pop(L, 1);
            LogError(host, outError);
            return false;
        }
        if (!lua_istable(L, -1)) {
            outError = FormatLuaError(entityId, scriptPath, "Load", "Script must return a table.");
            lua_pop(L, 1);
            LogError(host, outError);
            return false;
        }

        const int moduleIndex = lua_gettop(L);
        LuaScriptInstance instance;
        instance.scriptPath = scriptPath;
        instance.onCreateRef = FunctionRefFromField(L, moduleIndex, "OnCreate");
        instance.onStartRef = FunctionRefFromField(L, moduleIndex, "OnStart");
        instance.onUpdateRef = FunctionRefFromField(L, moduleIndex, "OnUpdate");
        instance.onFixedUpdateRef = FunctionRefFromField(L, moduleIndex, "OnFixedUpdate");
        instance.onDestroyRef = FunctionRefFromField(L, moduleIndex, "OnDestroy");

        lua_createtable(L, 0, 1);
        // Copy non-function script fields onto self so exposed/default values are available in methods.
        lua_pushnil(L);
        while (lua_next(L, moduleIndex) != 0) {
            // Stack: ... self key value
            if (lua_type(L, -2) == LUA_TSTRING && lua_type(L, -1) != LUA_TFUNCTION) {
                const char *key = lua_tostring(L, -2);
                if (key && strcmp(key, "Exposed") != 0 && strcmp(key, "Fields") != 0) {
                    lua_pushvalue(L, -2); // key copy
                    lua_pushvalue(L, -2); // value copy
                    lua_settable(L, -5);  // self[key] = value
                }
            }
            lua_pop(L, 1); // pop value, keep key for lua_next
        }
        PushEntityRef(L, host, entityId.c_str(), true);
        lua_setfield(L, -2, "entity");
        instance.selfRef = luaL_ref(L, LUA_REGISTRYINDEX);
        lua_pop(L, 1);

        host->instances[entityId] = std::move(instance);
        return true;
    }

    static bool StartInstanceInternal(LuaScriptHost *host,
                                      const std::string &entityId,
                                      std::string &outError) {
        if (!host || !host->L) { return false; }
        auto it = host->instances.find(entityId);
        if (it == host->instances.end()) { return true; }
        LuaScriptInstance &stored = it->second;
        if (!CallInstanceFunction(host, entityId, stored, stored.onCreateRef, "OnCreate", 0.0f, false, outError)) {
            return false;
        }
        if (!CallInstanceFunction(host, entityId, stored, stored.onStartRef, "OnStart", 0.0f, false, outError)) {
            return false;
        }
        return true;
    }

    static bool ReadVec2FromLuaTable(lua_State *L, int index, float &x, float &y) {
        if (!lua_istable(L, index)) { return false; }
        x = 0.0f;
        y = 0.0f;
        lua_getfield(L, index, "x");
        if (lua_isnumber(L, -1)) { x = static_cast<float>(lua_tonumber(L, -1)); }
        lua_pop(L, 1);
        lua_getfield(L, index, "y");
        if (lua_isnumber(L, -1)) { y = static_cast<float>(lua_tonumber(L, -1)); }
        lua_pop(L, 1);
        lua_rawgeti(L, index, 1);
        if (lua_isnumber(L, -1)) { x = static_cast<float>(lua_tonumber(L, -1)); }
        lua_pop(L, 1);
        lua_rawgeti(L, index, 2);
        if (lua_isnumber(L, -1)) { y = static_cast<float>(lua_tonumber(L, -1)); }
        lua_pop(L, 1);
        return true;
    }

    static bool ReadVec3SchemaValue(lua_State *L, int index, float &x, float &y, float &z) {
        float outVec[3] = {0, 0, 0};
        const float fallback[3] = {0, 0, 0};
        if (!ReadVec3FromLuaTable(L, index, outVec, fallback)) { return false; }
        x = outVec[0];
        y = outVec[1];
        z = outVec[2];
        return true;
    }

    static NSDictionary *BuildSchemaDescriptor(lua_State *L, int entryIndex, const std::string &fieldName, std::string &error) {
        if (!lua_istable(L, entryIndex)) { return nil; }
        lua_getfield(L, entryIndex, "type");
        const char *typeCString = lua_tostring(L, -1);
        std::string type = typeCString ? std::string(typeCString) : std::string();
        std::transform(type.begin(), type.end(), type.begin(), [](unsigned char ch) {
            return static_cast<char>(std::tolower(ch));
        });
        lua_pop(L, 1);
        if (type.empty()) {
            error = "Schema field '" + fieldName + "' is missing required 'type'.";
            return nil;
        }

        NSMutableDictionary *descriptor = [NSMutableDictionary dictionary];
        descriptor[@"name"] = [NSString stringWithUTF8String:fieldName.c_str()];
        descriptor[@"type"] = [NSString stringWithUTF8String:type.c_str()];

        lua_getfield(L, entryIndex, "default");
        if (type == "bool" || type == "boolean") {
            descriptor[@"default"] = @((bool) lua_toboolean(L, -1));
        } else if (type == "int" || type == "integer") {
            descriptor[@"default"] = @((int32_t) lua_tointeger(L, -1));
        } else if (type == "float" || type == "number") {
            descriptor[@"default"] = @((float) lua_tonumber(L, -1));
        } else if (type == "vec2") {
            float x = 0.0f, y = 0.0f;
            if (ReadVec2FromLuaTable(L, lua_gettop(L), x, y)) {
                descriptor[@"default"] = @[ @(x), @(y) ];
            } else {
                descriptor[@"default"] = @[ @0.0f, @0.0f ];
            }
        } else if (type == "vec3" || type == "color3" || type == "rgb") {
            float x = 0.0f, y = 0.0f, z = 0.0f;
            if (ReadVec3SchemaValue(L, lua_gettop(L), x, y, z)) {
                descriptor[@"default"] = @[ @(x), @(y), @(z) ];
            } else if (type == "color3" || type == "rgb") {
                descriptor[@"default"] = @[ @1.0f, @1.0f, @1.0f ];
            } else {
                descriptor[@"default"] = @[ @0.0f, @0.0f, @0.0f ];
            }
        } else if (type == "string") {
            const char *text = lua_tostring(L, -1);
            descriptor[@"default"] = text ? [NSString stringWithUTF8String:text] : @"";
        } else if (type == "entity" || type == "prefab") {
            if (lua_isnil(L, -1)) {
                descriptor[@"default"] = [NSNull null];
            } else {
                const char *text = lua_tostring(L, -1);
                descriptor[@"default"] = text ? [NSString stringWithUTF8String:text] : [NSNull null];
            }
        } else {
            lua_pop(L, 1);
            return nil;
        }
        lua_pop(L, 1);

        lua_getfield(L, entryIndex, "min");
        if (lua_isnumber(L, -1)) { descriptor[@"min"] = @((float) lua_tonumber(L, -1)); }
        lua_pop(L, 1);
        lua_getfield(L, entryIndex, "max");
        if (lua_isnumber(L, -1)) { descriptor[@"max"] = @((float) lua_tonumber(L, -1)); }
        lua_pop(L, 1);
        lua_getfield(L, entryIndex, "step");
        if (lua_isnumber(L, -1)) { descriptor[@"step"] = @((float) lua_tonumber(L, -1)); }
        lua_pop(L, 1);
        lua_getfield(L, entryIndex, "tooltip");
        if (lua_isstring(L, -1)) {
            descriptor[@"tooltip"] = [NSString stringWithUTF8String:lua_tostring(L, -1)];
        }
        lua_pop(L, 1);
        return descriptor;
    }

    static bool IsArraySchema(lua_State *L, int fieldsIndex) {
        const size_t length = lua_rawlen(L, fieldsIndex);
        if (length == 0) { return false; }
        lua_rawgeti(L, fieldsIndex, 1);
        const bool isEntryTable = lua_istable(L, -1);
        lua_pop(L, 1);
        return isEntryTable;
    }

    static bool CollectSchemaDescriptors(lua_State *L, int fieldsIndex, NSMutableArray *outDescriptors, std::string &error) {
        if (!lua_istable(L, fieldsIndex) || !outDescriptors) { return false; }
        if (IsArraySchema(L, fieldsIndex)) {
            const size_t length = lua_rawlen(L, fieldsIndex);
            for (size_t i = 1; i <= length; ++i) {
                lua_rawgeti(L, fieldsIndex, static_cast<lua_Integer>(i));
                if (!lua_istable(L, -1)) {
                    lua_pop(L, 1);
                    continue;
                }
                lua_getfield(L, -1, "name");
                const char *nameCString = lua_tostring(L, -1);
                std::string fieldName = nameCString ? std::string(nameCString) : std::string();
                lua_pop(L, 1);
                if (fieldName.empty()) {
                    lua_pop(L, 1);
                    continue;
                }
                NSDictionary *descriptor = BuildSchemaDescriptor(L, lua_gettop(L), fieldName, error);
                lua_pop(L, 1);
                if (!descriptor) { continue; }
                [outDescriptors addObject:descriptor];
            }
            return true;
        }

        std::set<std::string> visited;
        lua_getfield(L, fieldsIndex, "__order");
        if (lua_istable(L, -1)) {
            const size_t orderLength = lua_rawlen(L, -1);
            for (size_t i = 1; i <= orderLength; ++i) {
                lua_rawgeti(L, -1, static_cast<lua_Integer>(i));
                const char *nameCString = lua_tostring(L, -1);
                std::string fieldName = nameCString ? std::string(nameCString) : std::string();
                lua_pop(L, 1);
                if (fieldName.empty()) { continue; }
                lua_getfield(L, fieldsIndex, fieldName.c_str());
                NSDictionary *descriptor = BuildSchemaDescriptor(L, lua_gettop(L), fieldName, error);
                lua_pop(L, 1);
                if (!descriptor) { continue; }
                [outDescriptors addObject:descriptor];
                visited.insert(fieldName);
            }
        }
        lua_pop(L, 1);

        std::vector<std::string> names;
        lua_pushnil(L);
        while (lua_next(L, fieldsIndex) != 0) {
            if (lua_type(L, -2) == LUA_TSTRING) {
                const char *key = lua_tostring(L, -2);
                if (key && strcmp(key, "__order") != 0 && visited.find(key) == visited.end()) {
                    names.emplace_back(key);
                }
            }
            lua_pop(L, 1);
        }
        std::sort(names.begin(), names.end());
        for (const std::string &fieldName : names) {
            lua_getfield(L, fieldsIndex, fieldName.c_str());
            NSDictionary *descriptor = BuildSchemaDescriptor(L, lua_gettop(L), fieldName, error);
            lua_pop(L, 1);
            if (!descriptor) { continue; }
            [outDescriptors addObject:descriptor];
        }
        return true;
    }
}

extern "C" uint32_t MCELuaExtractScriptSchema(const char *scriptPath,
                                              const char *typeName,
                                              char *jsonBuffer,
                                              int32_t jsonBufferSize,
                                              char *errorBuffer,
                                              int32_t errorBufferSize) {
    if (!scriptPath || !jsonBuffer || jsonBufferSize <= 0) { return 0; }

    lua_State *L = luaL_newstate();
    if (!L) {
        WriteCString("Failed to initialize Lua state for schema extraction.", errorBuffer, errorBufferSize);
        return 0;
    }
    luaL_requiref(L, "_G", luaopen_base, 1); lua_pop(L, 1);
    luaL_requiref(L, LUA_TABLIBNAME, luaopen_table, 1); lua_pop(L, 1);
    luaL_requiref(L, LUA_STRLIBNAME, luaopen_string, 1); lua_pop(L, 1);
    luaL_requiref(L, LUA_MATHLIBNAME, luaopen_math, 1); lua_pop(L, 1);

    std::string error;
    NSMutableArray *descriptors = [NSMutableArray array];

    if (luaL_loadfile(L, scriptPath) != LUA_OK) {
        const char *text = lua_tostring(L, -1);
        error = text ? text : "Unable to load script.";
        lua_pop(L, 1);
        lua_close(L);
        WriteCString(error, errorBuffer, errorBufferSize);
        return 0;
    }
    if (lua_pcall(L, 0, 1, 0) != LUA_OK) {
        const char *text = lua_tostring(L, -1);
        error = text ? text : "Unable to execute script for schema extraction.";
        lua_pop(L, 1);
        lua_close(L);
        WriteCString(error, errorBuffer, errorBufferSize);
        return 0;
    }

    bool resolved = false;
    if (lua_istable(L, -1)) {
        lua_getfield(L, -1, "Exposed");
        if (!lua_istable(L, -1)) {
            lua_pop(L, 1);
            lua_getfield(L, -1, "Fields");
        }
        if (lua_istable(L, -1)) {
            resolved = CollectSchemaDescriptors(L, lua_gettop(L), descriptors, error);
        }
        lua_pop(L, 1);
    }

    if (!resolved && typeName && typeName[0] != 0) {
        lua_getglobal(L, typeName);
        if (lua_istable(L, -1)) {
            lua_getfield(L, -1, "Exposed");
            if (!lua_istable(L, -1)) {
                lua_pop(L, 1);
                lua_getfield(L, -1, "Fields");
            }
            if (lua_istable(L, -1)) {
                resolved = CollectSchemaDescriptors(L, lua_gettop(L), descriptors, error);
            }
            lua_pop(L, 1);
        }
        lua_pop(L, 1);
    }

    lua_pop(L, 1);
    lua_close(L);

    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:descriptors options:0 error:&jsonError];
    if (!jsonData || jsonError) {
        WriteCString("Failed to serialize Lua schema to JSON.", errorBuffer, errorBufferSize);
        return 0;
    }
    NSString *jsonText = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    if (!jsonText) {
        WriteCString("Failed to encode Lua schema JSON.", errorBuffer, errorBufferSize);
        return 0;
    }
    WriteCString(std::string([jsonText UTF8String]), jsonBuffer, jsonBufferSize);
    return 1;
}

extern "C" void *MCELuaRuntimeCreate(void *hostContext,
                                     LuaLogCallback logCallback,
                                     LuaEntityExistsCallback entityExistsCallback,
                                     LuaEntityGetNameCallback entityGetNameCallback,
                                     LuaEntityGetTransformCallback entityGetTransformCallback,
                                     LuaEntitySetTransformCallback entitySetTransformCallback,
                                     LuaEntityMoveCallback entityMoveCallback,
                                     LuaEntitySetMoveInputCallback entitySetMoveInputCallback,
                                     LuaEntitySetLookInputCallback entitySetLookInputCallback,
                                     LuaEntitySetSprintCallback entitySetSprintCallback,
                                     LuaEntityJumpCallback entityJumpCallback,
                                     LuaEntityIsGroundedCallback entityIsGroundedCallback,
                                     LuaEntityGetVelocityCallback entityGetVelocityCallback,
                                     LuaInputIsKeyDownCallback inputIsKeyDownCallback,
                                     LuaInputWasKeyPressedCallback inputWasKeyPressedCallback,
                                     LuaInputGetMouseDeltaCallback inputGetMouseDeltaCallback,
                                     LuaInputSetCursorModeCallback inputSetCursorModeCallback,
                                     LuaInputGetCursorModeCallback inputGetCursorModeCallback,
                                     LuaInputToggleCursorModeLockedCallback inputToggleCursorModeLockedCallback,
                                     LuaAssetGetNameCallback assetGetNameCallback) {
    LuaScriptHost *host = new LuaScriptHost();
    host->hostContext = hostContext;
    host->logCallback = logCallback;
    host->entityExistsCallback = entityExistsCallback;
    host->entityGetNameCallback = entityGetNameCallback;
    host->entityGetTransformCallback = entityGetTransformCallback;
    host->entitySetTransformCallback = entitySetTransformCallback;
    host->entityMoveCallback = entityMoveCallback;
    host->entitySetMoveInputCallback = entitySetMoveInputCallback;
    host->entitySetLookInputCallback = entitySetLookInputCallback;
    host->entitySetSprintCallback = entitySetSprintCallback;
    host->entityJumpCallback = entityJumpCallback;
    host->entityIsGroundedCallback = entityIsGroundedCallback;
    host->entityGetVelocityCallback = entityGetVelocityCallback;
    host->inputIsKeyDownCallback = inputIsKeyDownCallback;
    host->inputWasKeyPressedCallback = inputWasKeyPressedCallback;
    host->inputGetMouseDeltaCallback = inputGetMouseDeltaCallback;
    host->inputSetCursorModeCallback = inputSetCursorModeCallback;
    host->inputGetCursorModeCallback = inputGetCursorModeCallback;
    host->inputToggleCursorModeLockedCallback = inputToggleCursorModeLockedCallback;
    host->assetGetNameCallback = assetGetNameCallback;
    host->L = luaL_newstate();
    if (!host->L) {
        delete host;
        return nullptr;
    }
    luaL_requiref(host->L, "_G", luaopen_base, 1);
    lua_pop(host->L, 1);
    luaL_requiref(host->L, LUA_TABLIBNAME, luaopen_table, 1);
    lua_pop(host->L, 1);
    luaL_requiref(host->L, LUA_STRLIBNAME, luaopen_string, 1);
    lua_pop(host->L, 1);
    luaL_requiref(host->L, LUA_MATHLIBNAME, luaopen_math, 1);
    lua_pop(host->L, 1);
    RegisterGlobals(host);
    return host;
}

extern "C" void MCELuaRuntimeDestroy(void *runtimePtr) {
    LuaScriptHost *host = static_cast<LuaScriptHost *>(runtimePtr);
    if (!host) { return; }
    if (host->inputSetCursorModeCallback) {
        host->inputSetCursorModeCallback(host->hostContext, 0);
    }
    if (host->L) {
        for (auto &entry : host->instances) {
            ClearInstanceRefs(host->L, entry.second);
        }
        host->instances.clear();
        lua_close(host->L);
        host->L = nullptr;
    }
    delete host;
}

extern "C" uint32_t MCELuaRuntimeInstantiate(void *runtimePtr,
                                             const char *entityId,
                                             const char *scriptPath,
                                             char *errorBuffer,
                                             int32_t errorBufferSize) {
    LuaScriptHost *host = static_cast<LuaScriptHost *>(runtimePtr);
    if (!host || !entityId || !scriptPath) { return 0; }
    std::string error;
    const bool ok = InstantiateInternal(host, entityId, scriptPath, error);
    if (!ok) {
        WriteCString(error, errorBuffer, errorBufferSize);
    }
    return ok ? 1u : 0u;
}

extern "C" uint32_t MCELuaRuntimeReload(void *runtimePtr,
                                        const char *entityId,
                                        const char *scriptPath,
                                        char *errorBuffer,
                                        int32_t errorBufferSize) {
    LuaScriptHost *host = static_cast<LuaScriptHost *>(runtimePtr);
    if (!host || !entityId || !scriptPath) { return 0; }
    std::string ignored;
    DestroyInstanceInternal(host, entityId, &ignored);
    std::string error;
    const bool ok = InstantiateInternal(host, entityId, scriptPath, error);
    if (!ok) {
        WriteCString(error, errorBuffer, errorBufferSize);
    }
    return ok ? 1u : 0u;
}

extern "C" uint32_t MCELuaRuntimeUpdate(void *runtimePtr,
                                        const char *entityId,
                                        float dt,
                                        char *errorBuffer,
                                        int32_t errorBufferSize) {
    LuaScriptHost *host = static_cast<LuaScriptHost *>(runtimePtr);
    if (!host || !entityId || !host->L) { return 0; }
    auto it = host->instances.find(entityId);
    if (it == host->instances.end()) { return 1; }
    SetDeltaTime(host, dt);
    std::string error;
    const bool ok = CallInstanceFunction(host,
                                         entityId,
                                         it->second,
                                         it->second.onUpdateRef,
                                         "OnUpdate",
                                         dt,
                                         true,
                                         error);
    if (!ok) {
        WriteCString(error, errorBuffer, errorBufferSize);
    }
    return ok ? 1u : 0u;
}

extern "C" uint32_t MCELuaRuntimeFixedUpdate(void *runtimePtr,
                                             const char *entityId,
                                             float dt,
                                             char *errorBuffer,
                                             int32_t errorBufferSize) {
    LuaScriptHost *host = static_cast<LuaScriptHost *>(runtimePtr);
    if (!host || !entityId || !host->L) { return 0; }
    auto it = host->instances.find(entityId);
    if (it == host->instances.end()) { return 1; }
    SetDeltaTime(host, dt);
    std::string error;
    const bool ok = CallInstanceFunction(host,
                                         entityId,
                                         it->second,
                                         it->second.onFixedUpdateRef,
                                         "OnFixedUpdate",
                                         dt,
                                         true,
                                         error);
    if (!ok) {
        WriteCString(error, errorBuffer, errorBufferSize);
    }
    return ok ? 1u : 0u;
}

extern "C" uint32_t MCELuaRuntimeDestroyInstance(void *runtimePtr,
                                                 const char *entityId,
                                                 char *errorBuffer,
                                                 int32_t errorBufferSize) {
    LuaScriptHost *host = static_cast<LuaScriptHost *>(runtimePtr);
    if (!host || !entityId) { return 0; }
    std::string error;
    const bool ok = DestroyInstanceInternal(host, entityId, &error);
    if (!ok) {
        WriteCString(error, errorBuffer, errorBufferSize);
    }
    return ok ? 1u : 0u;
}

extern "C" uint32_t MCELuaRuntimeStartInstance(void *runtimePtr,
                                               const char *entityId,
                                               char *errorBuffer,
                                               int32_t errorBufferSize) {
    LuaScriptHost *host = static_cast<LuaScriptHost *>(runtimePtr);
    if (!host || !entityId) { return 0; }
    std::string error;
    const bool ok = StartInstanceInternal(host, entityId, error);
    if (!ok) {
        WriteCString(error, errorBuffer, errorBufferSize);
    }
    return ok ? 1u : 0u;
}

extern "C" uint32_t MCELuaRuntimeDispatchPhysicsEvent(void *runtimePtr,
                                                      const char *entityId,
                                                      const char *phase,
                                                      const char *otherEntityId,
                                                      char *errorBuffer,
                                                      int32_t errorBufferSize) {
    LuaScriptHost *host = static_cast<LuaScriptHost *>(runtimePtr);
    if (!host || !host->L || !entityId || !phase || !otherEntityId) { return 0; }
    auto it = host->instances.find(entityId);
    if (it == host->instances.end()) { return 1; }
    LuaScriptInstance &instance = it->second;
    if (instance.faulted) { return 0; }

    lua_State *L = host->L;
    lua_rawgeti(L, LUA_REGISTRYINDEX, instance.selfRef);
    if (!lua_istable(L, -1)) {
        lua_pop(L, 1);
        return 1;
    }
    lua_getfield(L, -1, phase);
    if (!lua_isfunction(L, -1)) {
        lua_pop(L, 2);
        return 1;
    }
    lua_rawgeti(L, LUA_REGISTRYINDEX, instance.selfRef);
    lua_pushstring(L, otherEntityId);
    if (lua_pcall(L, 2, 0, 0) != LUA_OK) {
        const char *errorText = lua_tostring(L, -1);
        std::string error = FormatLuaError(entityId, instance.scriptPath, phase, errorText ? errorText : "Unknown Lua error.");
        instance.lastError = error;
        instance.faulted = true;
        WriteCString(error, errorBuffer, errorBufferSize);
        lua_pop(L, 2);
        return 0;
    }
    lua_pop(L, 1);
    return 1;
}

extern "C" uint32_t MCELuaRuntimeSetField(void *runtimePtr,
                                          const char *entityId,
                                          const char *fieldName,
                                          int32_t fieldType,
                                          int32_t intValue,
                                          float numberValue,
                                          uint32_t boolValue,
                                          const char *stringValue,
                                          float vecX,
                                          float vecY,
                                          float vecZ) {
    LuaScriptHost *host = static_cast<LuaScriptHost *>(runtimePtr);
    if (!host || !host->L || !entityId || !fieldName) { return 0; }
    auto it = host->instances.find(entityId);
    if (it == host->instances.end()) { return 1; }
    LuaScriptInstance &instance = it->second;
    lua_State *L = host->L;
    lua_rawgeti(L, LUA_REGISTRYINDEX, instance.selfRef);
    if (!lua_istable(L, -1)) {
        lua_pop(L, 1);
        return 0;
    }
    switch (fieldType) {
        case 0:
            lua_pushboolean(L, boolValue != 0 ? 1 : 0);
            break;
        case 1:
            lua_pushinteger(L, intValue);
            break;
        case 2:
            lua_pushnumber(L, numberValue);
            break;
        case 3:
            PushVec2Table(L, vecX, vecY);
            break;
        case 4: {
            const float vec[3] = {vecX, vecY, vecZ};
            PushVec3Table(L, vec);
            break;
        }
        case 5: {
            const float vec[3] = {vecX, vecY, vecZ};
            PushVec3Table(L, vec);
            break;
        }
        case 6:
            lua_pushstring(L, stringValue ? stringValue : "");
            break;
        case 7:
            if (stringValue && stringValue[0] != 0) {
                PushEntityRef(L, host, stringValue, false);
            } else {
                lua_pushnil(L);
            }
            break;
        case 8:
            if (stringValue && stringValue[0] != 0) {
                PushPrefabRef(L, host, stringValue);
            } else {
                lua_pushnil(L);
            }
            break;
        default:
            lua_pop(L, 1);
            return 0;
    }
    lua_setfield(L, -2, fieldName);
    lua_pop(L, 1);
    return 1;
}

extern "C" uint32_t MCELuaRuntimeHasInstance(void *runtimePtr,
                                             const char *entityId) {
    LuaScriptHost *host = static_cast<LuaScriptHost *>(runtimePtr);
    if (!host || !entityId) { return 0; }
    auto it = host->instances.find(entityId);
    if (it == host->instances.end()) { return 0; }
    return it->second.faulted ? 0u : 1u;
}
