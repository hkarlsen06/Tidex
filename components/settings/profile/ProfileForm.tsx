'use client';

import { useState, useEffect, useRef, type ChangeEvent } from 'react';
import { Card } from '@appui/Card';
import { Input } from '@appui/Input';
import { Label } from '@appui/Label';
import { Button } from '@appui/Button';
import { Avatar, AvatarFallback, AvatarImage } from '@appui/Avatar';
import { updateProfileSettings } from '@/app/(app)/settings/_actions/updateSettings';
import { IconArrowsExchange, IconTrash } from '@tabler/icons-react';
import { useRouter } from 'next/navigation';

interface ProfileFormProps {
  initialData: {
    firstName: string;
    email: string;
    profilePictureUrl: string | null;
  };
}

export function ProfileForm({ initialData }: ProfileFormProps) {
  const router = useRouter();
  const [firstName, setFirstName] = useState(initialData.firstName);
  const [profilePictureUrl, setProfilePictureUrl] = useState(initialData.profilePictureUrl);
  const [isSaving, setIsSaving] = useState(false);
  const [isUploading, setIsUploading] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);
  const saveTimeoutRef = useRef<ReturnType<typeof setTimeout>>();
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
    saveTimeoutRef.current = setTimeout(async () => {
      setIsSaving(true);
      try {
        await updateProfileSettings({ firstName });
        router.refresh();
      } catch (error) {
        console.error('Failed to save profile:', error);
      } finally {
        setIsSaving(false);
      }
    }, 1000);

    return () => {
      if (saveTimeoutRef.current) {
        clearTimeout(saveTimeoutRef.current);
      }
    };
  }, [firstName, initialData.firstName, router]);

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
      setUploadError('Bildet må være mindre enn 5MB');
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
        setUploadError(errorPayload?.error ?? 'Kunne ikke laste opp bildet. Prøv igjen.');
        return;
      }

      const payload = (await response.json()) as { publicUrl: string };
      newUrl = payload.publicUrl;
    } catch (error) {
      console.error('Unexpected error uploading profile picture:', error);
      setUploadError('Kunne ikke laste opp bildet. Prøv igjen.');
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
      setUploadError('Kunne ikke lagre profilbildet.');
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
        setUploadError(errorPayload?.error ?? 'Kunne ikke fjerne profilbildet.');
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
      setUploadError('Kunne ikke fjerne profilbildet.');
    } finally {
      setIsUploading(false);
    }
  };

  const mailHref = (() => {
    const subject = encodeURIComponent('Endring av e-postadresse');
    const body = encodeURIComponent(`Jeg ønsker å endre epost-addresssen min fra ${initialData.email} til (ny epost).`);
    return `mailto:kkarlsen06@kkarlsen.dev?subject=${subject}&body=${body}`;
  })();

  return (
    <Card className="p-6">
      <div className="space-y-6">
        <div className="space-y-5">
          <div className="space-y-4">
            <h2 className="text-2xl font-semibold">Personlig informasjon</h2>
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
                  <IconArrowsExchange className="h-4 w-4" aria-hidden />
                  {isUploading ? 'Laster opp…' : profilePictureUrl ? 'Bytt bilde' : 'Last opp bilde'}
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
                    <IconTrash className="h-4 w-4" aria-hidden />
                    Fjern bilde
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
            <Label htmlFor="firstName">Navn</Label>
            <Input
              id="firstName"
              value={firstName}
              onChange={(e) => setFirstName(e.target.value)}
              placeholder="Ditt navn"
              disabled={isSaving}
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="email">E-post</Label>
            <Input
              id="email"
              value={initialData.email}
              disabled
              className="opacity-60"
            />
            <p className="text-xs text-text-secondary">
              For å endre e-postadresse,{' '}
              <a
                className="underline"
                href={mailHref}
              >
                ta kontakt
              </a>
              .
            </p>
          </div>
        </div>
      </div>
    </Card>
  );
}
