import * as Yup from 'yup';
import { CustomManifestValues, ManifestFormData } from '../data/dataTypes';
import {
  getMaxFileSizeMessage,
  validateFileSize,
  validateFileName,
  validateFileType,
  INCORRECT_TYPE_FILE_MESSAGE,
} from '../../../../../common/utils';
const INCORRECT_FILENAME =
  'Must have a yaml, yml, json, yaml.patch or yml.patch extension and can not contain /.';

const UNIQUE_FOLDER_FILENAME = 'Ensure unique file names to avoid conflicts and errors.';

export const getUniqueValidationSchema = Yup.string().test(
  'unique',
  UNIQUE_FOLDER_FILENAME,
  (value, testContext: Yup.TestContext) => {
    const context = testContext.options.context as Yup.TestContext & { values?: ManifestFormData };
    if (!context || !context.values) {
      return testContext.createError({
        message: 'Unexpected error: Yup test context should contain form values',
      });
    }

    const values = context.values.manifests.map((manifest) => manifest.filename);
    return values.filter((path) => path === value).length === 1;
  },
);

export const getFormViewManifestsValidationSchema = Yup.object<ManifestFormData>({
  manifests: Yup.array<CustomManifestValues>().of(
    Yup.object({
      folder: Yup.mixed().required('Required'),
      filename: Yup.string()
        .required('Required')
        .min(1, 'Number of characters must be 1-255')
        .max(255, 'Number of characters must be 1-255')
        .test('not-correct-filename', INCORRECT_FILENAME, (value: string) => {
          return validateFileName(value);
        })
        .concat(getUniqueValidationSchema),
      manifestYaml: Yup.string().when('filename', {
        is: (filename: string) => !filename.includes('patch'),
        then: () =>
          Yup.string()
            .required('Required')
            .test('not-big-file', getMaxFileSizeMessage, validateFileSize)
            .test('not-valid-file', INCORRECT_TYPE_FILE_MESSAGE, validateFileType),
        otherwise: () =>
          Yup.string()
            .required('Required')
            .test('not-big-file', getMaxFileSizeMessage, validateFileSize), // Validation of file content is not required if filename contains 'patch'
      }),
    }),
  ),
});
