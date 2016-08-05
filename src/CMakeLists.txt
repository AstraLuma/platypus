### CMakeLists automatically created with AutoVala
### Do not edit

set (DATADIR "${CMAKE_INSTALL_PREFIX}/${CMAKE_INSTALL_DATAROOTDIR}")
set (PKGDATADIR "${DATADIR}/platypus")
set (GETTEXT_PACKAGE "platypus")
set (RELEASE_NAME "platypus")
set (CMAKE_C_FLAGS "")
set (PREFIX ${CMAKE_INSTALL_PREFIX})
set (VERSION "1.0.0")
set (TESTSRCDIR "${CMAKE_SOURCE_DIR}")
set (DOLLAR "$")

configure_file (${CMAKE_SOURCE_DIR}/src/Config.vala.cmake ${CMAKE_BINARY_DIR}/src/Config.vala)
add_definitions(-DGETTEXT_PACKAGE=\"${GETTEXT_PACKAGE}\")
set (VERSION "1.0.0")
add_definitions (${DEPS_CFLAGS})
link_libraries ( ${DEPS_LIBRARIES} )
link_directories ( ${DEPS_LIBRARY_DIRS} )
find_package (Vala REQUIRED)
include (ValaVersion)
ensure_vala_version ("0.32" MINIMUM)
include (ValaPrecompile)

set (VALA_PACKAGES ${VALA_PACKAGES} gio-2.0)
set (VALA_PACKAGES ${VALA_PACKAGES} gtk+-3.0)
set (VALA_PACKAGES ${VALA_PACKAGES} posix)
set (VALA_PACKAGES ${VALA_PACKAGES} vte-2.91)
set (VALA_PACKAGES ${VALA_PACKAGES} glib-2.0)
set (VALA_PACKAGES ${VALA_PACKAGES} gobject-2.0)

set (APP_SOURCES ${APP_SOURCES} ${CMAKE_CURRENT_BINARY_DIR}/Config.vala)
set (APP_SOURCES ${APP_SOURCES} ForegroundProcessDialog.vala)
set (APP_SOURCES ${APP_SOURCES} Platypus.vala)
set (APP_SOURCES ${APP_SOURCES} PlatypusWindow.vala)
set (APP_SOURCES ${APP_SOURCES} SearchToolbar.vala)
set (APP_SOURCES ${APP_SOURCES} TerminalWidget.vala)

if (DEBUG)
	set (COMPILE_OPTIONS ${COMPILE_OPTIONS} -D DEBUG)
	set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DDEBUG " )
	set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -DDEBUG " )
endif ()
set (COMPILE_OPTIONS ${COMPILE_OPTIONS} -g )

vala_precompile(VALA_C platypus
	${APP_SOURCES}
PACKAGES
	${VALA_PACKAGES}
OPTIONS
	${COMPILE_OPTIONS}
)

add_executable(platypus ${VALA_C})


install(TARGETS
	platypus
RUNTIME DESTINATION
	${CMAKE_INSTALL_BINDIR}
)
if(HAVE_VALADOC)
	valadoc(platypus
		${CMAKE_BINARY_DIR}/valadoc/platypus
		${APP_SOURCES}
	PACKAGES
		${VALA_PACKAGES}
	CUSTOM_VAPIS
		${CUSTOM_VAPIS_LIST}
	)
	install(DIRECTORY
		${CMAKE_BINARY_DIR}/valadoc
	DESTINATION
		${CMAKE_INSTALL_DATAROOTDIR}/doc/platypus
	)
endif()
