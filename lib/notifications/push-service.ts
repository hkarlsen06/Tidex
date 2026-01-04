import { Capacitor } from "@capacitor/core"
import {
  registerPushDevice,
  unregisterPushDevice,
  updatePushDeviceLastSeen,
} from "@/app/actions/push-device"

export interface PushNotificationPayload {
  type:
    | "shared_shift_created"
    | "shared_shift_updated"
    | "shared_shift_deleted"
    | "shift_reminder"
    | "admin_broadcast"
    | "share_started"
    | "feedback_submitted"
    | "feedback_responded"
  owner_id?: string
  shift_dates?: string // Comma-separated dates for calendar highlighting
  deeplink?: string // For admin broadcasts, share_started, and feedback notifications
  feedback_id?: string // For feedback notifications
}

class PushNotificationService {
  private initialized = false
  private currentToken: string | null = null

  async initialize(): Promise<void> {
    if (this.initialized || !Capacitor.isNativePlatform()) {
      return
    }

    try {
      // Dynamic import to avoid loading on web
      const { FirebaseMessaging } = await import("@capacitor-firebase/messaging")
      const { Device } = await import("@capacitor/device")
      const { App } = await import("@capacitor/app")

      // Check/request permission
      const permResult = await FirebaseMessaging.requestPermissions()
      if (permResult.receive !== "granted") {
        console.log("[Push] Permission denied")
        return
      }

      // Get FCM token
      const { token } = await FirebaseMessaging.getToken()
      if (token) {
        console.log("[Push] FCM token received")
        this.currentToken = token

        // Get device info for registration
        const deviceInfo = await Device.getInfo()
        const deviceId = await Device.getId()
        const appInfo = await App.getInfo()

        await this.saveTokenToServer(token, {
          deviceId: deviceId.identifier,
          deviceModel: deviceInfo.model,
          appVersion: appInfo.version,
        })
      }

      // Listen for token refresh
      FirebaseMessaging.addListener("tokenReceived", async ({ token }) => {
        console.log("[Push] Token refreshed")
        this.currentToken = token

        const deviceId = await Device.getId()
        await this.saveTokenToServer(token, {
          deviceId: deviceId.identifier,
        })
      })

      // Listen for notification tap (app was in background/killed)
      FirebaseMessaging.addListener(
        "notificationActionPerformed",
        ({ notification }) => {
          console.log("[Push] Notification tapped:", notification)
          const data = notification.data as PushNotificationPayload
          if (data) {
            this.handleNotificationTap(data)
          }
        }
      )

      // Listen for notification received while app is in foreground
      FirebaseMessaging.addListener(
        "notificationReceived",
        ({ notification }) => {
          console.log("[Push] Notification received in foreground:", notification)
          // Could show in-app toast here
        }
      )

      this.initialized = true
    } catch (error) {
      console.error("[Push] Initialization failed:", error)
    }
  }

  private async saveTokenToServer(
    fcmToken: string,
    metadata: {
      deviceId?: string
      deviceModel?: string
      appVersion?: string
    }
  ): Promise<void> {
    // Use server action to register push device (accesses internal.push_devices)
    const result = await registerPushDevice({
      fcmToken,
      platform: Capacitor.getPlatform() as "ios" | "android" | "web",
      deviceId: metadata.deviceId,
      deviceModel: metadata.deviceModel,
      appVersion: metadata.appVersion,
    })

    if (!result.success) {
      console.error("[Push] Failed to save token:", result.error)
    } else {
      console.log("[Push] Token saved successfully")
    }
  }

  private handleNotificationTap(payload: PushNotificationPayload): void {
    const locale = this.getLocale()
    let url: string

    // Check for generic deeplink first (used by admin_broadcast, share_started, feedback notifications)
    if (payload.deeplink) {
      // Deeplink is already validated server-side to start with /
      const path = payload.deeplink.startsWith('/') ? payload.deeplink : `/${payload.deeplink}`
      url = `/${locale}${path}`
    } else if (payload.type === "shift_reminder") {
      // Navigate to shifts page, optionally with date
      // shift_dates contains comma-separated dates, use first one for navigation
      const firstDate = payload.shift_dates?.split(",")[0]
      if (firstDate) {
        url = `/${locale}/shifts?date=${firstDate}`
      } else {
        url = `/${locale}/shifts`
      }
    } else {
      // Shared shift notification - navigate to shared calendar with date highlighting
      // shift_dates is comma-separated list of dates to highlight in the calendar
      const params = new URLSearchParams()
      params.set("user", payload.owner_id || "")
      if (payload.shift_dates) {
        params.set("dates", payload.shift_dates) // Pass all dates for highlighting
      }
      url = `/${locale}/sharing?${params.toString()}`
    }

    // Navigate
    if (typeof window !== "undefined") {
      window.location.href = url
    }
  }

  private getLocale(): string {
    if (typeof window !== "undefined") {
      // Extract from URL
      const match = window.location.pathname.match(/^\/(no|en)\//)
      return match?.[1] ?? "no"
    }
    return "no"
  }

  async removeTokenOnLogout(): Promise<void> {
    if (!this.currentToken) return

    // Use server action to remove token (accesses internal.push_devices)
    await unregisterPushDevice(this.currentToken)

    this.currentToken = null
  }

  async updateLastSeen(): Promise<void> {
    if (!this.currentToken) return

    // Use server action to update last seen (accesses internal.push_devices)
    await updatePushDeviceLastSeen(this.currentToken)
  }
}

export const pushNotificationService = new PushNotificationService()
