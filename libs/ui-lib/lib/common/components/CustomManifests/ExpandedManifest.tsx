import React from 'react';
import { Language } from '@patternfly/react-code-editor';
import { ExpandableSection, Grid, GridItem, TextInput } from '@patternfly/react-core';
import { useField } from 'formik';
// todo
import { OcmInputField, OcmCodeField } from '../../../ocm/components/ui/OcmFormFields';
import { CustomManifestValues } from './types';
import { FolderDropdown } from './FolderDropdown';
import { CustomManifestComponentProps } from './propTypes';
import { PopoverIcon } from '../..';
import { MAX_FILE_SIZE_BYTES } from '../../configurations';
import { fileSize } from '../../utils';

const getDownloadFileName = (manifestIdx: number, value: CustomManifestValues) => {
  return value.folder && value.filename
    ? `${value.folder}/${value.filename.replace('.yaml', '')}`
    : `custom_manifest_${manifestIdx}`;
};

const ExpandedManifest = ({ fieldName, manifestIdx, yamlOnly }: CustomManifestComponentProps) => {
  const [{ value }] = useField<CustomManifestValues>({
    name: fieldName,
  });

  return (
    <ExpandableSection
      isDetached
      key={manifestIdx}
      isExpanded
      data-testid={`expanded-manifest-${manifestIdx}`}
    >
      <Grid hasGutter span={12}>
        {!yamlOnly && (
          <>
            <GridItem span={6}>
              <TextInput
                hidden={true}
                name={`${fieldName}.fakeId`}
                data-testid={`fakeId-${manifestIdx}`}
                id={`fakeId-${manifestIdx}`}
              />
              <FolderDropdown name={`${fieldName}.folder`} data-testid={`folder-${manifestIdx}`} />
            </GridItem>
            <GridItem span={6}>
              <OcmInputField
                name={`${fieldName}.filename`}
                isRequired
                data-testid={`filename-${manifestIdx}`}
                helperText={`Use yaml, yml or JSON file types. File size must not exceed ${fileSize(
                  MAX_FILE_SIZE_BYTES,
                  0,
                  'si',
                )}.`}
                label={
                  <>
                    <span>File name</span>{' '}
                    <PopoverIcon
                      bodyContent={
                        'File name determines order of executing manifests during the installation. For example "manifest1.yaml" will be applied before "manifest2.yaml"'
                      }
                    />
                  </>
                }
              />
            </GridItem>
          </>
        )}
        <GridItem span={12}>
          <OcmCodeField
            language={Language.yaml}
            name={`${fieldName}.manifestYaml`}
            dataTestid={`yamlContent-${manifestIdx}`}
            label="Content"
            isRequired
            downloadFileName={getDownloadFileName(manifestIdx, value)}
            isReadOnly
            showCustomControls
          />
        </GridItem>
      </Grid>
    </ExpandableSection>
  );
};

export default ExpandedManifest;
