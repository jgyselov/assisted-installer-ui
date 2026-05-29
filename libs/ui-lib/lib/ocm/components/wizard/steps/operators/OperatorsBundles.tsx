import * as React from 'react';
import { Gallery, GalleryItem, Stack, StackItem, Title } from '@patternfly/react-core';
import {
  Bundle,
  PreflightHardwareRequirements,
} from '@openshift-assisted/types/assisted-installer-service';
import { singleClusterBundles } from '../../../../../common';
import { useFeature } from '../../../../hooks/use-feature';
import { BundleCard } from './fields';

export const OperatorsBundles = ({
  bundles,
  allBundles,
  preflightRequirements,
  searchTerm,
}: {
  bundles: Bundle[];
  allBundles: Bundle[];
  preflightRequirements: PreflightHardwareRequirements | undefined;
  searchTerm?: string;
}) => {
  const isSingleClusterFeatureEnabled = useFeature('ASSISTED_INSTALLER_SINGLE_CLUSTER_FEATURE');

  return (
    <Stack hasGutter>
      <StackItem>
        <Title headingLevel="h2" size="lg">
          {allBundles.length > 0 ? 'Bundles' : ''}
        </Title>
      </StackItem>
      <StackItem>
        <Gallery hasGutter minWidths={{ default: '350px' }}>
          {(isSingleClusterFeatureEnabled
            ? allBundles.filter((b) => b.id && singleClusterBundles.includes(b.id))
            : allBundles
          ).map((bundle) => (
            <GalleryItem key={bundle.id}>
              <BundleCard
                bundle={bundles.find((b) => b.id === bundle.id) || bundle}
                bundles={bundles}
                preflightRequirements={preflightRequirements}
                searchTerm={searchTerm}
              />
            </GalleryItem>
          ))}
        </Gallery>
      </StackItem>
    </Stack>
  );
};
