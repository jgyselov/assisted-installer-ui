import { K8sResourceCommon } from '@openshift-console/dynamic-plugin-sdk';
import { StatusCondition } from './shared';

type VolumeAccessMode = 'ReadWriteOnce' | 'ReadOnlyMany' | 'ReadWriteMany' | 'ReadWriteOncePod';
type StorageConfig = {
  accessModes: VolumeAccessMode[];
  resources: {
    requests: {
      storage: string; // i.e. 10G, 200M
    };
  };
};

export type OsImage = {
  cpuArchitecture: string;
  openshiftVersion: string;
  url: string;
  version: string;
};

export type AgentServiceConfigConditionType = 'DeploymentsHealthy' | 'ReconcileCompleted';

export type AgentServiceConfigK8sResource = K8sResourceCommon & {
  spec: {
    databaseStorage: StorageConfig;
    filesystemStorage: StorageConfig;
    imageStorage: StorageConfig;
    osImages?: OsImage[];
  };
  status?: {
    conditions?: StatusCondition<AgentServiceConfigConditionType>[];
  };
};
