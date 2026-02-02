'use client';

import { useState, useEffect, useRef, useTransition, type ChangeEvent } from 'react';
import { Card } from '@/components/app/Card';
import { Input } from '@/components/app/Input';
import { Label } from '@/components/app/Label';
import { Button } from '@/components/app/Button';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/app/Avatar';
import { updateProfileSettings } from '@/app/[locale]/(app)/settings/_actions/updateSettings';
import { ArrowRightLeft, Trash2 } from 'lucide-react';
import { useRouter } from 'next/navigation';
import { EmailChangeCard } from './EmailChangeCard';
import { useTranslations } from '@/lib/i18n/client';
import { supabase } from '@/lib/supabase/browser';

interface ProfileFormProps {
  initialData: {
    firstName: string;
    email: string;
    profilePictureUrl: string | null;
  };
}

export function ProfileForm({ initialData }: ProfileFormProps) {
  const { t } = useTranslations();
  const router = useRouter();
  const [_isPending, startTransition] = useTransition();
  const [firstName, setFirstName] = useState(initialData.firstName);
  const [profilePictureUrl, setProfilePictureUrl] = useState(initialData.profilePictureUrl);
  const [isSaving, setIsSaving] = useState(false);
  const [isUploading, setIsUploading] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);
  const [showEmailChangeCard, setShowEmailChangeCard] = useState(false);
  const saveTimeoutRef = useRef<ReturnType<typeof setTimeout>>(undefined);
  const fileInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    setProfilePictureUrl(initialData.profilePictureUrl);
  }, [initialData.profilePictureUrl]);

  // Auto-save when firstName changes
  useEffect(() => {
    // Clear any pending save
    if (saveTimeoutRef.current) {
      clearTimeout(saveTimeoutRef.current);
    }

    // Don't save if value hasn't changed
    if (firstName === initialData.firstName) {
      return;
    }

    // Debounce save for 1 second
    saveTimeoutRef.current = setTimeout(() => {
      startTransition(async () => {
        setIsSaving(true);
        try {
          await updateProfileSettings({ firstName });
          // Refresh client-side session to get new JWT with updated user_metadata.
          // This triggers SupabaseListener's onAuthStateChange which calls router.refresh()
          // with the new cookies already set, ensuring the layout reads the updated name.
          await supabase.auth.refreshSession();
        } catch (error) {
          console.error('Failed to save profile:', error);
        } finally {
          setIsSaving(false);
        }
      });
    }, 1000);

    return () => {
      if (saveTimeoutRef.current) {
        clearTimeout(saveTimeoutRef.current);
      }
    };
  }, [firstName, initialData.firstName]);

  const getInitials = (name: string) => {
    return name
      .split(' ')
      .map(n => n[0])
      .join('')
      .toUpperCase()
      .slice(0, 2);
  };

  const handleUploadClick = () => {
    if (fileInputRef.current) {
      fileInputRef.current.click();
    }
  };


  const handleProfilePictureUpload = async (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = '';

    if (!file) return;

    if (file.size > 5 * 1024 * 1024) {
      setUploadError(t.pages.settings.profile.personalInfo.errors.imageTooBig);
      return;
    }

    setIsUploading(true);
    setUploadError(null);

    const formData = new FormData();
    formData.append('file', file);
    if (profilePictureUrl) {
      formData.append('previousUrl', profilePictureUrl);
    }

    let newUrl: string | null = null;

    try {
      const response = await fetch('/api/profile-picture', {
        method: 'POST',
        body: formData,
      });

      if (!response.ok) {
        const errorPayload = await response.json().catch(() => null);
        console.error('Failed to upload profile picture via API route:', errorPayload ?? response.statusText);
        setUploadError(errorPayload?.error ?? t.pages.settings.profile.personalInfo.errors.uploadFailed);
        return;
      }

      const payload = (await response.json()) as { publicUrl: string };
      newUrl = payload.publicUrl;
    } catch (error) {
      console.error('Unexpected error uploading profile picture:', error);
      setUploadError(t.pages.settings.profile.personalInfo.errors.uploadFailed);
      return;
    }

    try {
      await updateProfileSettings({
        firstName,
        profilePictureUrl: newUrl,
      });

      setProfilePictureUrl(newUrl);
      router.refresh();
    } catch (error) {
      console.error('Failed to save profile picture:', error);
      setUploadError(t.pages.settings.profile.personalInfo.errors.saveFailed);
      if (newUrl) {
        try {
          await fetch(`/api/profile-picture?url=${encodeURIComponent(newUrl)}`, {
            method: 'DELETE',
          });
        } catch (cleanupError) {
          console.error('Failed to clean up uploaded profile picture after error:', cleanupError);
        }
      }
    } finally {
      setIsUploading(false);
    }
  };

  const handleRemoveProfilePicture = async () => {
    if (!profilePictureUrl) return;

    setIsUploading(true);
    setUploadError(null);

    try {
      const response = await fetch(`/api/profile-picture?url=${encodeURIComponent(profilePictureUrl)}`, {
        method: 'DELETE',
      });

      if (!response.ok) {
        const errorPayload = await response.json().catch(() => null);
        console.error('Failed to delete profile picture via API route:', errorPayload ?? response.statusText);
        setUploadError(errorPayload?.error ?? t.pages.settings.profile.personalInfo.errors.removeFailed);
        return;
      }

      await updateProfileSettings({
        firstName,
        profilePictureUrl: null,
      });

      setProfilePictureUrl(null);
      router.refresh();
    } catch (error) {
      console.error('Failed to remove profile picture:', error);
      setUploadError(t.pages.settings.profile.personalInfo.errors.removeFailed);
    } finally {
      setIsUploading(false);
    }
  };

  const handleEmailChangeComplete = () => {
    setShowEmailChangeCard(false);
    router.refresh();
  };

  return (
    <>
    <Card className="p-6">
      <div className="space-y-6">
        <div className="space-y-5">
          <div className="space-y-4">
            <h2 className="text-2xl font-semibold">{t.pages.settings.profile.personalInfo.title}</h2>
            <div className="flex items-center gap-6">
              <Avatar className="h-24 w-24">
                <AvatarImage src={profilePictureUrl || undefined} />
                <AvatarFallback className="bg-surface-secondary text-text-primary text-lg">
                  {getInitials(firstName || initialData.email)}
                </AvatarFallback>
              </Avatar>
              <div className="flex flex-col items-center gap-3">
                <input
                  ref={fileInputRef}
                  type="file"
                  accept="image/*"
                  className="hidden"
                  onChange={handleProfilePictureUpload}
                />
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  className="w-36 justify-center gap-2"
                  onClick={handleUploadClick}
                  disabled={isUploading}
                >
                  <ArrowRightLeft className="h-4 w-4" aria-hidden />
                  {isUploading ? t.pages.settings.profile.personalInfo.uploadingImage : profilePictureUrl ? t.pages.settings.profile.personalInfo.changeImage : t.pages.settings.profile.personalInfo.uploadImage}
                </Button>
                {profilePictureUrl && (
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    className="w-36 justify-center gap-2"
                    onClick={handleRemoveProfilePicture}
                    disabled={isUploading}
                  >
                    <Trash2 className="h-4 w-4" aria-hidden />
                    {t.pages.settings.profile.personalInfo.removeImage}
                  </Button>
                )}
                {uploadError && (
                  <p className="text-center text-sm text-destructive">
                    {uploadError}
                  </p>
                )}
              </div>
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="firstName">{t.pages.settings.profile.personalInfo.nameLabel}</Label>
            <Input
              id="firstName"
              value={firstName}
              onChange={(e) => setFirstName(e.target.value)}
              disabled={isSaving}
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="email">{t.pages.settings.profile.personalInfo.emailLabel}</Label>
            <Input
              id="email"
              value={initialData.email}
              disabled
              className="opacity-60"
            />
            <p className="text-xs text-text-secondary">
              <button
                type="button"
                className="underline hover:text-text-primary transition-colors"
                onClick={() => setShowEmailChangeCard(true)}
              >
                {t.pages.settings.profile.personalInfo.changeEmail}
              </button>
            </p>
          </div>
        </div>
      </div>
    </Card>
    {showEmailChangeCard && (
      <EmailChangeCard
        currentEmail={initialData.email}
        onCancel={() => setShowEmailChangeCard(false)}
        onComplete={handleEmailChangeComplete}
      />
    )}
    </>
  );
}
