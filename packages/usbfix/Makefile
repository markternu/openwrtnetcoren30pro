include $(TOPDIR)/rules.mk

PKG_NAME:=usbfix
PKG_VERSION:=1.0
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/usbfix
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Netcore N30 Pro USB VBUS fix helpers (diagnostics)
  PKGARCH:=all
endef

define Package/usbfix/description
  Diagnostic helpers for the USB VBUS (GPIO23 / regulator-usb-vbus) power fix
  on Netcore N30 Pro. Provides /usr/sbin/usb-fix-check.
endef

define Build/Compile
endef

define Package/usbfix/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/usb-fix-check $(1)/usr/sbin/usb-fix-check
	$(INSTALL_DIR) $(1)/etc
	$(INSTALL_DATA) ./files/usb-fix-id $(1)/etc/usb-fix-id
endef

$(eval $(call BuildPackage,usbfix))
