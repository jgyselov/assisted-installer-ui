import React from 'react';
import { useNavigate } from 'react-router-dom-v5-compat';
import {
  Button,
  ButtonVariant,
  PageSectionVariants,
  TextContent,
  Text,
  PageSection,
} from '@patternfly/react-core';
import { AddCircleOIcon } from '@patternfly/react-icons/dist/js/icons/add-circle-o-icon';
import {
  ResourceUIState,
  Alerts,
  LoadingState,
  ErrorState,
  EmptyState,
  useAlerts,
  AlertsContextProvider,
  REDUCED_POLLING_INTERVAL,
} from '../../../common';
import ClustersTable from './ClustersTable';
import { fetchClustersAsync, deleteCluster } from '../../store/slices/clusters/slice';
import { handleApiError, getApiErrorMessage } from '../../../common/api';
import ClusterBreadcrumbs from './ClusterBreadcrumbs';
import { ClustersService } from '../../services';
import { useTranslation } from '../../../common/hooks/use-translation-wrapper';
import ClusterPollingErrorModal from '../clusterDetail/ClusterPollingErrorModal';
import { Cluster } from '@openshift-assisted/types/assisted-installer-service';
import { useSelectorDay1, useDispatchDay1 } from '../../store';
import {
  selectClustersUIState,
  selectClusterTableRows,
} from '../../store/slices/clusters/selectors';

const Clusters = () => {
  const navigate = useNavigate();
  const { LOADING, EMPTY, POLLING_ERROR, RELOADING } = ResourceUIState;
  const { addAlert } = useAlerts();
  const { t } = useTranslation();
  const clusterRows = useSelectorDay1(selectClusterTableRows(t));
  const clustersUIState = useSelectorDay1(selectClustersUIState);
  const uiState = React.useRef(clustersUIState);
  if (clustersUIState !== RELOADING) {
    uiState.current = clustersUIState;
  }
  const dispatch = useDispatchDay1();
  const deleteClusterAsync = React.useCallback(
    async (clusterId: Cluster['id']) => {
      try {
        await ClustersService.remove(clusterId);
        dispatch(deleteCluster(clusterId));
      } catch (e) {
        handleApiError(e, () =>
          addAlert({
            title: 'Cluster could not be deleted',
            message: getApiErrorMessage(e),
          }),
        );
      }
    },
    [dispatch, addAlert],
  );

  const fetchClusters = React.useCallback(() => void dispatch(fetchClustersAsync()), [dispatch]);

  React.useEffect(() => {
    // Fetch immediately on mount
    fetchClusters();

    // Set up polling for subsequent updates
    const timer = setInterval(() => {
      fetchClusters();
    }, REDUCED_POLLING_INTERVAL);

    return () => clearInterval(timer);
  }, [fetchClusters]);

  switch (uiState.current) {
    case LOADING:
      return (
        <PageSection variant={PageSectionVariants.light} isFilled>
          <LoadingState />
        </PageSection>
      );
    case EMPTY:
      return (
        <PageSection variant={PageSectionVariants.light} isFilled>
          <EmptyState
            icon={AddCircleOIcon}
            title="Create new assisted cluster"
            content="There are no clusters yet. This wizard is going to guide you through the OpenShift cluster deployment."
            primaryAction={
              <Button
                variant={ButtonVariant.primary}
                onClick={() => navigate(`~new`)}
                id="empty-state-new-cluster-button"
                data-ouia-id="button-create-new-cluster"
              >
                Create New Cluster
              </Button>
            }
          />
        </PageSection>
      );
    default:
      if (clusterRows.length === 0 && uiState.current === POLLING_ERROR) {
        return (
          <PageSection variant={PageSectionVariants.light} isFilled>
            <ErrorState title="Failed to fetch clusters." fetchData={fetchClusters} />
          </PageSection>
        );
      } else {
        return (
          <>
            <ClusterBreadcrumbs />
            <PageSection variant={PageSectionVariants.light}>
              <TextContent>
                <Text component="h1">Assisted Clusters</Text>
              </TextContent>
            </PageSection>
            <PageSection variant={PageSectionVariants.light} isFilled>
              <Alerts />
              <ClustersTable rows={clusterRows} deleteCluster={deleteClusterAsync} />
            </PageSection>
            {uiState.current === POLLING_ERROR && (
              <ClusterPollingErrorModal
                title={'Failed to fetch clusters'}
                content={
                  'There was an error retrieving data. Check your connection and try refreshing the page.'
                }
              />
            )}
          </>
        );
      }
  }
};

const ClustersPage = () => (
  <AlertsContextProvider>
    <Clusters />
  </AlertsContextProvider>
);

export default ClustersPage;
