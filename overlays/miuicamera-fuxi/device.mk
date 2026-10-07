#
# SPDX-License-Identifier: Apache-2.0
#
# 现代 MiuiCamera 端口不依赖 Xiaomi Framework / miui.jar。
# 需要的是: 预编译 APK + 几条 Xiaomi JNI/HIDL client + shim + sepolicy。
# vendor makefile 不存在时整段被跳过，ROM 仍用 Aperture，能编过。
#

MIUICAMERA_PATH := device/xiaomi/miuicamera-fuxi

$(call inherit-product-if-exists, vendor/xiaomi/miuicamera-fuxi/miuicamera-fuxi-vendor.mk)

PRODUCT_PACKAGES += \
    libgui_shim_miuicamera

PRODUCT_COPY_FILES += \
    $(MIUICAMERA_PATH)/configs/public.libraries-xiaomi.txt:$(TARGET_COPY_OUT_SYSTEM)/etc/public.libraries-xiaomi.txt \
    $(MIUICAMERA_PATH)/configs/privapp-permissions-miuicamera.xml:$(TARGET_COPY_OUT_SYSTEM)/etc/permissions/privapp-permissions-miuicamera.xml \
    $(MIUICAMERA_PATH)/configs/miuicamera-hiddenapi-package-allowlist.xml:$(TARGET_COPY_OUT_SYSTEM)/etc/sysconfig/miuicamera-hiddenapi-package-allowlist.xml

PRODUCT_SOONG_NAMESPACES += \
    $(MIUICAMERA_PATH)
