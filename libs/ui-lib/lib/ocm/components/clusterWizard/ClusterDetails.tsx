import React from 'react';
import { useHistory } from 'react-router-dom';
import { useDispatch } from 'react-redux';
import { useAlerts, LoadingState, ClusterWizardStep, ErrorState } from '../../../common';
import { usePullSecret } from '../../hooks';
import { getApiErrorMessage, handleApiError, isUnknownServerError } from '../../../common/api';
import { setServerUpdateError, updateCluster } from '../../store/slices/current-cluster/slice';
import { useClusterWizardContext } from './ClusterWizardContext';
import { canNextClusterDetails, ClusterWizardFlowStateNew } from './wizardTransition';
import { useManagedDomains, useUsedClusterNames } from '../../hooks';
import { useOpenshiftVersionsContext } from './OpenshiftVersionsContext';
import ClusterDetailsForm from './ClusterDetailsForm';
import ClusterWizardNavigation from './ClusterWizardNavigation';
import { routeBasePath } from '../../config';
import {
  ClusterDetailsUpdateParams,
  ClustersService,
  ClusterCreateParamsWithStaticNetworking,
  UISettingService,
} from '../../services';
import { Cluster, InfraEnv } from '@openshift-assisted/types/assisted-installer-service';

type ClusterDetailsProps = {
  cluster?: Cluster;
  infraEnv?: InfraEnv;
};

const ClusterDetails = ({ cluster, infraEnv }: ClusterDetailsProps) => {
  const clusterWizardContext = useClusterWizardContext();
  const managedDomains = useManagedDomains();
  const { addAlert, clearAlerts } = useAlerts();
  const history = useHistory();
  const dispatch = useDispatch();
  const { usedClusterNames } = useUsedClusterNames(cluster?.id || '');
  const pullSecret = usePullSecret();
  const {
    error: errorOCPVersions,
    loading: loadingOCPVersions,
    latestVersions: versions,
  } = useOpenshiftVersionsContext();

  const handleClusterUpdate = React.useCallback(
    async (
      clusterId: Cluster['id'],
      params: ClusterDetailsUpdateParams,
      addCustomManifests: boolean,
    ) => {
      clearAlerts();

      try {
        const { data: updatedCluster } = await ClustersService.update(
          clusterId,
          cluster?.tags,
          params,
        );
        await clusterWizardContext.updateUISettings({ addCustomManifests });
        dispatch(updateCluster(updatedCluster));

        canNextClusterDetails({ cluster: updatedCluster }) && clusterWizardContext.moveNext();
      } catch (e) {
        handleApiError(e, () =>
          addAlert({ title: 'Failed to update the cluster', message: getApiErrorMessage(e) }),
        );
        if (isUnknownServerError(e as Error)) {
          dispatch(setServerUpdateError());
        }
      }
    },
    [clearAlerts, addAlert, dispatch, cluster?.tags, clusterWizardContext],
  );

  const handleClusterCreate = React.useCallback(
    async (params: ClusterCreateParamsWithStaticNetworking, addCustomManifests: boolean) => {
      clearAlerts();
      try {
        const cluster = await ClustersService.create(params);
        history.push(`${routeBasePath}/clusters/${cluster.id}`, ClusterWizardFlowStateNew);
        await UISettingService.update(cluster.id, { addCustomManifests });
      } catch (e) {
        handleApiError(e, () =>
          addAlert({ title: 'Failed to create new cluster', message: getApiErrorMessage(e) }),
        );
        if (isUnknownServerError(e as Error)) {
          dispatch(setServerUpdateError());
        }
      }
    },
    [clearAlerts, history, addAlert, dispatch],
  );

  const navigation = <ClusterWizardNavigation cluster={cluster} />;
  if (pullSecret === undefined || !managedDomains || loadingOCPVersions || !usedClusterNames) {
    return (
      <ClusterWizardStep navigation={navigation}>
        <LoadingState />
      </ClusterWizardStep>
    );
  }

  if (!cluster && errorOCPVersions) {
    return (
      <ClusterWizardStep navigation={navigation}>
        <ErrorState title="Failed to retrieve OpenShift versions" />
      </ClusterWizardStep>
    );
  }

  return (
    <ClusterDetailsForm
      cluster={cluster}
      pullSecret={pullSecret}
      managedDomains={managedDomains}
      ocpVersions={versions}
      usedClusterNames={usedClusterNames}
      moveNext={() => clusterWizardContext.moveNext()}
      handleClusterUpdate={handleClusterUpdate}
      handleClusterCreate={handleClusterCreate}
      navigation={navigation}
      infraEnv={infraEnv}
    />
  );
};

export default ClusterDetails;
