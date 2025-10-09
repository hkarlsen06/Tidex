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
    <div className="space-y-6">
      <Card className="p-6">
        <div className="space-y-6">
          <div>
            <h3 className="text-lg font-semibold">Eksporter data</h3>
            <p className="text-sm text-text-secondary mt-1">
              Last ned alle dine vakter og innstillinger som en JSON-fil
            </p>
          </div>

          <Separator />

          <div className="flex items-center justify-between">
            <div>
              <p className="font-medium">Eksporter til JSON</p>
              <p className="text-sm text-text-secondary">
                Inkluderer alle vakter, innstillinger og preferanser
              </p>
            </div>
            <Button onClick={handleExport} disabled={isExporting}>
              <Download className="h-4 w-4 mr-2" />
              {isExporting ? 'Eksporterer...' : 'Eksporter'}
            </Button>
          </div>
        </div>
      </Card>

      <Card className="p-6">
        <div className="space-y-6">
          <div>
            <h3 className="text-lg font-semibold">Importer data</h3>
            <p className="text-sm text-text-secondary mt-1">
              Last opp en tidligere eksportert JSON-fil for å gjenopprette data
            </p>
          </div>

          <Separator />

          <div className="flex items-center justify-between">
            <div>
              <p className="font-medium">Importer fra JSON</p>
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
                disabled={isImporting}
              />
              <label htmlFor="import-file">
                <Button asChild disabled={isImporting}>
                  <span className="cursor-pointer">
                    <Upload className="h-4 w-4 mr-2" />
                    {isImporting ? 'Importerer...' : 'Importer'}
                  </span>
                </Button>
              </label>
            </div>
          </div>
        </div>
      </Card>

      <Card className="p-6 border-yellow-200 dark:border-yellow-900">
        <div className="space-y-2">
          <h3 className="font-semibold text-yellow-600 dark:text-yellow-400">
            Viktig informasjon
          </h3>
          <ul className="text-sm text-text-secondary space-y-1 list-disc list-inside">
            <li>Eksporterte filer inneholder all din personlige informasjon</li>
            <li>Oppbevar eksporterte filer sikkert</li>
            <li>Import vil overskrive eksisterende data - lag en sikkerhetskopi først</li>
            <li>Denne funksjonen er under utvikling og vil bli fullført snart</li>
          </ul>
        </div>
      </Card>
    </div>
  );
}
