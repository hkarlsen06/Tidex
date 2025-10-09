'use client';

import { useState } from 'react';
import { Card } from '@appui/Card';
import { Button } from '@appui/Button';
import { Separator } from '@appui/Separator';
import { Download, Upload } from 'lucide-react';

export function DataForm() {
  const [isExporting, setIsExporting] = useState(false);
  const [isImporting, setIsImporting] = useState(false);

  const handleExport = async () => {
    setIsExporting(true);
    try {
      // TODO: Implement export functionality
      // This would fetch all user data and create a JSON file
      console.log('Export functionality to be implemented');
      alert('Export funksjonen kommer snart!');
    } catch (error) {
      console.error('Failed to export data:', error);
    } finally {
      setIsExporting(false);
    }
  };

  const handleImport = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    setIsImporting(true);
    try {
      // TODO: Implement import functionality
      // This would read the JSON file and import all data
      console.log('Import functionality to be implemented');
      alert('Import funksjonen kommer snart!');
    } catch (error) {
      console.error('Failed to import data:', error);
    } finally {
      setIsImporting(false);
      event.target.value = ''; // Reset file input
    }
  };

  return (
    <div className="space-y-6 opacity-50 pointer-events-none">
      <Card className="p-6">
        <div className="space-y-6">
          <div>
            <h3 className="text-lg font-semibold text-text-muted">Eksporter data</h3>
            <p className="text-sm text-text-secondary mt-1">
              Last ned alle dine vakter og innstillinger som en JSON-fil
            </p>
          </div>

          <Separator />

          <div className="flex items-center justify-between">
            <div>
              <p className="font-medium text-text-muted">Eksporter til JSON</p>
              <p className="text-sm text-text-secondary">
                Inkluderer alle vakter, innstillinger og preferanser
              </p>
            </div>
            <Button onClick={handleExport} disabled>
              <Download className="h-4 w-4 mr-2" />
              Eksporter
            </Button>
          </div>
        </div>
      </Card>

      <Card className="p-6">
        <div className="space-y-6">
          <div>
            <h3 className="text-lg font-semibold text-text-muted">Importer data</h3>
            <p className="text-sm text-text-secondary mt-1">
              Last opp en tidligere eksportert JSON-fil for å gjenopprette data
            </p>
          </div>

          <Separator />

          <div className="flex items-center justify-between">
            <div>
              <p className="font-medium text-text-muted">Importer fra JSON</p>
              <p className="text-sm text-text-secondary">
                Dette vil overskrive eksisterende data
              </p>
            </div>
            <div>
              <input
                type="file"
                accept=".json"
                onChange={handleImport}
                className="hidden"
                id="import-file"
                disabled
              />
              <label htmlFor="import-file">
                <Button asChild disabled>
                  <span>
                    <Upload className="h-4 w-4 mr-2" />
                    Importer
                  </span>
                </Button>
              </label>
            </div>
          </div>
        </div>
      </Card>

      <Card className="p-6 border-yellow-200 dark:border-yellow-900 opacity-100">
        <div className="space-y-2">
          <h3 className="font-semibold text-yellow-600 dark:text-yellow-400">
            Kommer snart
          </h3>
          <p className="text-sm text-text-secondary">
            Data import og eksport funksjonen er under utvikling og vil bli tilgjengelig i en fremtidig oppdatering.
          </p>
        </div>
      </Card>
    </div>
  );
}
