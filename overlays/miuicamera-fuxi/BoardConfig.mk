#
# SPDX-License-Identifier: Apache-2.0
#

-include vendor/xiaomi/miuicamera-fuxi/BoardConfigVendor.mk

MIUICAMERA_PATH := device/xiaomi/miuicamera-fuxi

TARGET_SYSTEM_PROP += $(MIUICAMERA_PATH)/system.prop

BOARD_VENDOR_SEPOLICY_DIRS += $(MIUICAMERA_PATH)/sepolicy/vendor
