import { Capacitor } from "@capacitor/core"
import { supabase } from "@/lib/supabase/browser"

export interface PushNotificationPayload {
  type:
    | "shared_shift_created"
    | "shared_shift_updated"
    | "shared_shift_deleted"
    | "shift_reminder"
  shift_id?: string
  owner_id?: string
  shift_date?: string
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
    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user) {
      console.log("[Push] No user logged in, skipping token save")
      return
    }

    // Upsert with ON CONFLICT on fcm_token
    // This handles:
    // 1. New device registration
    // 2. Same device, same user (updates metadata)
    // 3. Same device, different user (updates user_id - account switch)
    const { error } = await supabase.from("push_devices").upsert(
      {
        user_id: user.id,
        fcm_token: fcmToken,
        platform: Capacitor.getPlatform() as "ios" | "android",
        device_id: metadata.deviceId,
        device_model: metadata.deviceModel,
        app_version: metadata.appVersion,
        last_seen_at: new Date().toISOString(),
      },
      {
        onConflict: "fcm_token",
      }
    )

    if (error) {
      console.error("[Push] Failed to save token:", error)
    } else {
      console.log("[Push] Token saved successfully")
    }
  }

  private handleNotificationTap(payload: PushNotificationPayload): void {
    const locale = this.getLocale()
    let url: string

    if (payload.type === "shift_reminder") {
      // Navigate to shifts page, optionally with date
      if (payload.shift_date) {
        url = `/${locale}/shifts?date=${payload.shift_date}`
      } else {
        url = `/${locale}/shifts`
      }
    } else {
      // Shared shift notification - navigate to shared calendar with highlight
      url = `/${locale}/sharing?user=${payload.owner_id}&highlight=${payload.shift_id}&date=${payload.shift_date}`
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

    // Remove this specific token
    await supabase
      .from("push_devices")
      .delete()
      .eq("fcm_token", this.currentToken)

    this.currentToken = null
  }

  async updateLastSeen(): Promise<void> {
    if (!this.currentToken) return

    await supabase
      .from("push_devices")
      .update({ last_seen_at: new Date().toISOString() })
      .eq("fcm_token", this.currentToken)
  }
}

export const pushNotificationService = new PushNotificationService()
