/* tslint:disable */
/* eslint-disable */
/**
 * Account Management Service API
 * Manage user subscriptions and clusters
 *
 * The version of the OpenAPI document: 0.0.1
 *
 *
 * NOTE: This class is auto generated by OpenAPI Generator (https://openapi-generator.tech).
 * https://openapi-generator.tech
 * Do not edit the class manually.
 */

// May contain unused imports in some cases
// @ts-ignore
import { SelfServiceLandingPageSchemaConfigTryLearn } from './self-service-landing-page-schema-config-try-learn';
// May contain unused imports in some cases
// @ts-ignore
import { SelfServiceLandingPageSchemaEstate } from './self-service-landing-page-schema-estate';

/**
 *
 * @export
 * @interface SelfServiceLandingPageSchema
 */
export interface SelfServiceLandingPageSchema {
  /**
   *
   * @type {SelfServiceLandingPageSchemaConfigTryLearn}
   * @memberof SelfServiceLandingPageSchema
   */
  configTryLearn?: SelfServiceLandingPageSchemaConfigTryLearn;
  /**
   *
   * @type {SelfServiceLandingPageSchemaEstate}
   * @memberof SelfServiceLandingPageSchema
   */
  estate?: SelfServiceLandingPageSchemaEstate;
}