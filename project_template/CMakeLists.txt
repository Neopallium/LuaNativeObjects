#
# Lua bindings for lib__mod_name__
#
cmake_minimum_required(VERSION 3.18)

project(lua-__mod_name__ C)

set(BUILD_SHARED_LIBS TRUE)

set(CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake)

set(INSTALL_CMOD share/lua/cmod CACHE PATH "Directory to install Lua binary modules (configure lua via LUA_CPATH)")

set(COMMON_CFLAGS "${CFLAGS}")
set(COMMON_LDFLAGS)
set(COMMON_LIBS)

## Lua 5.x
include(FindLua)
if(NOT ${LUA_FOUND})
    message(FATAL_ERROR "The FindLua module could not find lua :-(")
endif()
set(COMMON_LIBS "${COMMON_LIBS};${LUA_LIBRARIES}")

## Lib__Mod_name__
include(FindPkgConfig)
pkg_search_module(__MOD_NAME__ REQUIRED lib__mod_name__)
set(COMMON_CFLAGS "${COMMON_CFLAGS} ${__MOD_NAME___CFLAGS}")
set(COMMON_LDFLAGS "${COMMON_LDFLAGS} ${__MOD_NAME___LDFLAGS}")
set(COMMON_LIBS "${COMMON_LIBS};${__MOD_NAME___LIBRARIES}")

## LuaNativeObjects
include(LuaNativeObjects)

include_directories(${CMAKE_CURRENT_SOURCE_DIR}
                    ${CMAKE_CURRENT_BINARY_DIR}
                    ${LUA_INCLUDE_DIR})

## Lua__Mod_name__
set(LUA___MOD_NAME___SRC
	__mod_name__.nobj.lua
)

if(${USE_PRE_GENERATED_BINDINGS})
	set(LUA___MOD_NAME___SRC src/pre_generated-__mod_name__.nobj.c)
else()
	# Generate Lua bindings.
	GenLuaNativeObjects(LUA___MOD_NAME___SRC)
endif()

add_library(lua-__mod_name__ MODULE ${LUA___MOD_NAME___SRC})
target_link_libraries(lua-__mod_name__ ${COMMON_LIBS})
set_target_properties(lua-__mod_name__ PROPERTIES PREFIX "")
set_target_properties(lua-__mod_name__ PROPERTIES COMPILE_FLAGS "${COMMON_CFLAGS}")
set_target_properties(lua-__mod_name__ PROPERTIES OUTPUT_NAME __mod_name__)

install(TARGETS lua-__mod_name__
        DESTINATION "${INSTALL_CMOD}")

