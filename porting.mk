include $(PORT_BUILD)/localvar.mk
include $(PORT_BUILD)/prebuilt.mk

#> Start of global variable
# The global variable could be used in local makefile, and the name
# would not be changed in future
TMP_DIR     := .build
ZIP_DIR     := $(TMP_DIR)/ZIP
OUT_ZIP     := $(TMP_DIR)/$(OUT_ZIP_FILE)
TOOL_DIR    := $(PORT_ROOT)/tools
APKTOOL     := $(TOOL_DIR)/apktool
SIGN        := $(TOOL_DIR)/sign.sh
ADDMIUI     := $(TOOL_DIR)/add_miui_smail.sh
SYSOUT_DIR  := $(OUT_SYS_PATH)
#< End of global variable

JARS        := services android.policy framework
BLDAPKS     := $(addprefix $(TMP_DIR)/,$(addsuffix .apk,$(APPS)))
JARS_OUTDIR := $(addsuffix .jar.out,$(JARS))
APPS_OUTDIR := $(APPS) framework-res
BLDJARS     := $(addprefix $(TMP_DIR)/,$(addsuffix .jar,$(JARS)))
PHN_BLDJARS := $(addsuffix -phone,$(BLDJARS))
ZIP_BLDJARS := $(addsuffix -tozip,$(BLDJARS))

SIGNAPKS    := 
TOZIP_APKS  :=
CLEANJAR    :=
CLEANMIUIAPP:=
RELEASE_MIUI:=
RELEASE_PATH:= $(PORT_ROOT)/miui
MAKE_ATTOP  := make -C $(ANDROID_TOP)

#
# Extract the jar file from ZIP file and replaced the modified smails
# with MIUI features, and these smali files are stored in xxxx.jar.out
# $1: the jar name, such as services
# $2: the dir under build for apktool-decoded files, such as .build/services
define JAR_template
$(TMP_DIR)/$(1).jar-phone:$(TMP_DIR)/$(1).jar
	adb push $$< /system/framework/$(1).jar

$(TMP_DIR)/$(1).jar-tozip:$(TMP_DIR)/$(1).jar
	cp $$< $(ZIP_DIR)/system/framework/$(1).jar

$(TMP_DIR)/$(1).jar: $(2)_miui
	@echo build $$@...
	@echo --------------------------------------------
	cp -r $(1).jar.out/ $(2)
	$(ADDMIUI) $(2)_miui $(2)
	$(APKTOOL) b $(2) $$@

$(2)_miui: $(OUT_JAR_PATH)/$(1).jar
	$(APKTOOL) d -f $$< $$@

ifeq ($(USE_ANDROID_OUT),true)
$(OUT_JAR_PATH)/$(1).jar: $(ERR_REPORT)
	$(MAKE_ATTOP) $(1)

CLEANJAR += clean-$(1)
clean-$(1):
	$(MAKE_ATTOP) clean-$(1)

RELEASE_MIUI += $(RELEASE_PATH)/system/framework/$(1).jar
$(RELEASE_PATH)/system/framework/$(1).jar: $(OUT_JAR_PATH)/$(1).jar
	mkdir -p $(RELEASE_PATH)/system/framework
	cp $$< $$@
endif

# targets for initial workspace
$(1).jar.out:  $(ZIP_FILE)
	@unzip $(ZIP_FILE) system/framework/$(1).jar -d $(TMP_DIR)
	@$(APKTOOL) d -f $(TMP_DIR)/system/framework/$(1).jar $$@
	@rm $(TMP_DIR)/system/framework/$(1).jar

endef

#
# To apktool build one apk from the decoded dirctory under .build
# $1: the apk name, such as LogsProvider
# $2: the dir name, might be different from apk name
# $3: to specify if the smali files should be decoded from MIUI first
define APP_template
$(TMP_DIR)/$(1).apk: $(3) $(TMP_DIR)
	@echo build $$@...
	@echo --------------------------------------------
	cp -r $(2) $(TMP_DIR)
	$(APKTOOL) b  $(TMP_DIR)/$(2) $$@

ifeq ($(1),framework-miui-res)
$(3): $(OUT_JAR_PATH)/$(1).apk
	$(APKTOOL) d -f $(OUT_JAR_PATH)/$(1).apk $(3)
	@rm -rf $(3)/res
else
$(3): $(OUT_APK_PATH)/$(1).apk
	$(APKTOOL) d -f $(OUT_APK_PATH)/$(1).apk $(3)
endif

endef

#
# To prepare the workspace to modify the APKs from zip file
# $1 the apk name, also the dir name to save the smali files
# $2 the apk location under system, such as app or framework
define APP_WS_template
$(1): $(ZIPFILE)
	@unzip $(ZIP_FILE) system/$(2)/$(1).apk -d $(TMP_DIR)
	@$(APKTOOL) d -f $(TMP_DIR)/system/$(2)/$(1).apk $$@
	@rm $(TMP_DIR)/system/$(2)/$(1).apk

endef

#
# Used to sign one single file, e.g: make .build/LogsProvider.apk.sign
# for zipfile target, just to copy the unsigned file to correct ZIP-directory.
# also create a seperate target for command line, such as : make LogsProvider.apk.sign
# $1: the apk file need to be signed
# $2: the path/filename in the phone
define SIGN_template
SIGNAPKS += $(1).sign
$(notdir $(1)).sign $(1).sign: $(1)
	@echo sign apk $(1) and push to phone as $(2)...
	@echo --------------------------------------------
	java -jar $(TOOL_DIR)/signapk.jar $(TOOL_DIR)/platform.x509.pem $(TOOL_DIR)/platform.pk8 $(1) $(1).signed
	adb push $(1).signed $(2)

TOZIP_APKS += $(1)-tozip
$(1)-tozip : $(1)
	@echo cp apks-unsinged to zip dirs
	cp $(1) $(ZIP_DIR)$(2)
endef

#
# Used to build and clean the miui apk, e.g: make clean-Launcher2
# $1: the apk name
# $2: the dir name
define BUILD_CLEAN_APP_template
ifeq ($(USE_ANDROID_OUT),true)
$(OUT_APK_PATH)/$(1).apk:
	$(MAKE_ATTOP) $(1)

CLEANMIUIAPP += clean-$(1)
clean-$(1):
	$(MAKE_ATTOP) $$@

RELEASE_MIUI += $(RELEASE_PATH)/system/app/$(1).apk
$(RELEASE_PATH)/system/app/$(1).apk: $(OUT_APK_PATH)/$(1).apk
	mkdir -p $(RELEASE_PATH)/system/app
	cp $$< $$@
endif
endef

zipone: zipfile $(ACT_AFTER_ZIP)

#> TARGETS EXPANSION START
$(foreach jar, $(JARS), \
	$(eval $(call JAR_template,$(jar),$(TMP_DIR)/$(jar))))

$(foreach app, $(APPS) framework-res, \
	$(eval $(call APP_template,$(app),$(app))))
$(foreach app, $(MIUIAPPS_MOD) framework-miui-res, \
	$(eval $(call APP_template,$(app),$(app),$(TMP_DIR)/$(app))))

$(foreach app, $(APPS) $(MIUIAPPS_MOD), \
	$(eval $(call SIGN_template,$(TMP_DIR)/$(app).apk,/system/app/$(app).apk)))
$(foreach app, $(MIUIAPPS), \
	$(eval $(call SIGN_template,$(OUT_APK_PATH)/$(app).apk,/system/app/$(app).apk)))

$(eval $(call SIGN_template,$(TMP_DIR)/framework-miui-res.apk,/system/framework/framework-miui-res.apk))

$(eval $(call SIGN_template,$(TMP_DIR)/framework-res.apk,/system/framework/framework-res.apk))

$(foreach app, $(MIUIAPPS) $(MIUIAPPS_MOD), $(eval $(call BUILD_CLEAN_APP_template,$(app))))

$(foreach app, $(APPS), \
	$(eval $(call APP_WS_template,$(app),app)))
$(eval $(call APP_WS_template,framework-res,framework))
#< TARGET EXPANSION END

#> TARGET FOR ZIPFILE START
$(TMP_DIR):
	@mkdir -p $(TMP_DIR)

$(ZIP_DIR): $(TMP_DIR) $(ZIP_FILE)
	unzip $(ZIP_FILE) -d $@

remove-rund-apks:
	@echo To remove all unnecessary apks:
	rm -f $(addprefix $(ZIP_DIR)/system/app/, $(addsuffix .apk, $(RUNDAPKS)))

pre-zip-misc: add-miui-prebuilt

ifeq ($(USE_ANDROID_OUT),true)
RELEASE_MIUI += release-miui-prebuilt
endif
	
zipfile: $(ZIP_DIR) $(ZIP_BLDJARS) $(TOZIP_APKS) $(ACT_PRE_ZIP)
	$(SIGN) sign.zip $(ZIP_DIR)
	cd $(ZIP_DIR); zip -r ../../$(OUT_ZIP) ./
	@echo The output zip file is: $(OUT_ZIP)

#< TARGET FOR ZIPFILE END

include $(PORT_BUILD)/util.mk

