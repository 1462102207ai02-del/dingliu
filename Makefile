THEOS_PACKAGE_SCHEME = rootless
TARGET := iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WechatDuo
WechatDuo_FILES = Tweak.m WDCatalog.m WDPrefs.m WDStyle.m WDSettings.m WDDiag.m
WechatDuo_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
WechatDuo_CFLAGS = -fobjc-arc -fblocks -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations
WechatDuo_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk
