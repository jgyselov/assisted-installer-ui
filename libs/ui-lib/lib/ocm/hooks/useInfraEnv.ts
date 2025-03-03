import React from 'react';
import useInfraEnvId from './useInfraEnvId';
import { CpuArchitecture } from '../../common';
import { getErrorMessage } from '../../common/utils';
import { InfraEnvsAPI } from '../services/apis';
import InfraEnvIdsCacheService from '../services/InfraEnvIdsCacheService';
import {
  Cluster,
  InfraEnv,
  InfraEnvUpdateParams,
} from '@openshift-assisted/types/assisted-installer-service';

export default function useInfraEnv(
  clusterId: Cluster['id'],
  cpuArchitecture: CpuArchitecture,
  clusterName?: string,
  pullSecret?: string,
  openshiftVersion?: string,
): {
  infraEnv?: InfraEnv;
  error?: string;
  isLoading: boolean;
  updateInfraEnv: (infraEnvUpdateParams: InfraEnvUpdateParams) => Promise<InfraEnv>;
} {
  const [infraEnv, setInfraEnv] = React.useState<InfraEnv>();
  const [error, setError] = React.useState('');
  const { infraEnvId, error: infraEnvIdError } = useInfraEnvId(
    clusterId,
    cpuArchitecture,
    clusterName,
    pullSecret,
    openshiftVersion,
  );

  const getInfraEnv = React.useCallback(async () => {
    try {
      if (infraEnvId) {
        const { data: infraEnv } = await InfraEnvsAPI.get(infraEnvId);
        setInfraEnv(infraEnv);
      }
    } catch (e) {
      // Invalidate this cluster's cached data
      InfraEnvIdsCacheService.removeInfraEnvId(clusterId, CpuArchitecture.USE_DAY1_ARCHITECTURE);
      setError(getErrorMessage(e));
    }
  }, [clusterId, infraEnvId]);

  const updateInfraEnv = React.useCallback(
    async (infraEnvUpdateParams: InfraEnvUpdateParams) => {
      if (!infraEnvId) {
        throw 'updateInfraEnv should not be called before infra env was loaded';
      }
      InfraEnvsAPI.abortLastGetRequest();
      const { data } = await InfraEnvsAPI.update(infraEnvId, infraEnvUpdateParams);
      setInfraEnv(data);
      return data;
    },
    [infraEnvId],
  );

  React.useEffect(() => {
    if (infraEnvIdError) {
      setError(infraEnvIdError);
    } else {
      if (!infraEnv) {
        void getInfraEnv();
      }
    }
  }, [getInfraEnv, infraEnv, infraEnvId, infraEnvIdError]);

  return { infraEnv, error, isLoading: !infraEnv && !error, updateInfraEnv };
}
