import React from 'react';
import { CpuArchitecture, OpenshiftVersionOptionType } from '../../common';
import { getApiErrorMessage, handleApiError } from '../../common/api';
import { SupportedOpenshiftVersionsAPI } from '../services/apis';
import { getKeys } from '../../common/utils';
import { Cluster, OpenshiftVersion } from '@openshift-assisted/types/assisted-installer-service';

type OpenShiftVersion = Cluster['openshiftVersion'];

type UseOpenshiftVersionsType = {
  versions: OpenshiftVersionOptionType[];
  isSupportedOpenShiftVersion: (version: OpenShiftVersion) => boolean;
  getCpuArchitectures: (version: OpenShiftVersion) => CpuArchitecture[];
  error?: { title: string; message: string };
  loading: boolean;
};

const sortVersions = (versions: OpenshiftVersionOptionType[]) => {
  return versions.sort((version1, version2) =>
    version1.value.localeCompare(version2.value, undefined, { numeric: true }),
  );
};

const supportedVersionLevels = ['production', 'maintenance'];

export default function useOpenshiftVersions(latest_release?: boolean): UseOpenshiftVersionsType {
  const [versions, setVersions] = React.useState<OpenshiftVersionOptionType[]>([]);
  const [error, setError] = React.useState<UseOpenshiftVersionsType['error']>();

  const findVersionItemByVersion = React.useCallback(
    (version: OpenShiftVersion) => {
      return versions.find(({ value: versionKey }) => {
        // For version 4.10 match 4.10, 4.10.3, not 4.1, 4.1.5
        const versionNameMatch = new RegExp(`^${versionKey}(\\..+)?$`);
        return versionNameMatch.test(version || '');
      });
    },
    [versions],
  );

  const fetchOpenshiftVersions = React.useCallback(async (latest_release: boolean) => {
    try {
      const { data } = await SupportedOpenshiftVersionsAPI.list(latest_release);

      const versions: OpenshiftVersionOptionType[] = getKeys(data).map((key) => {
        const versionItem = data[key] as OpenshiftVersion;
        const version = versionItem.displayName;
        return {
          label: `OpenShift ${version}`,
          value: key as string,
          version,
          default: Boolean(versionItem.default),
          supportLevel: versionItem.supportLevel,
          cpuArchitectures: versionItem.cpuArchitectures as CpuArchitecture[],
        };
      });

      setVersions(sortVersions(versions));
    } catch (e) {
      handleApiError(e, (e) => {
        setError({
          title: 'Failed to retrieve list of supported OpenShift versions.',
          message: getApiErrorMessage(e),
        });
      });
    }
  }, []);

  const isSupportedOpenShiftVersion = React.useCallback(
    (version: OpenShiftVersion) => {
      if (versions.length === 0) {
        // Till the data are loaded
        return true;
      }
      const selectedVersion = findVersionItemByVersion(version);
      return supportedVersionLevels.includes(selectedVersion?.supportLevel || '');
    },
    [findVersionItemByVersion, versions.length],
  );

  const getCpuArchitectures = React.useCallback(
    (version: OpenShiftVersion) => {
      // TODO (multi-arch) confirm this is correctly retrieving the associated version
      const matchingVersion = findVersionItemByVersion(version);
      return matchingVersion?.cpuArchitectures ?? [];
    },
    [findVersionItemByVersion],
  );

  React.useEffect(() => {
    void fetchOpenshiftVersions(latest_release ?? false);
  }, [latest_release, fetchOpenshiftVersions]);

  return {
    error,
    loading: !error && versions.length === 0,
    versions,
    isSupportedOpenShiftVersion,
    getCpuArchitectures,
  };
}
