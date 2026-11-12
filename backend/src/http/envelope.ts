import type { AppError, ErrorCode } from '../errors/app-error.js';

export interface OkResponse<T> {
  data: T;
}

export interface ErrorBody {
  code: ErrorCode;
  message: string;
  remainingMeters?: number | null;
}

export interface ErrorResponse {
  error: ErrorBody;
}

export function ok<T>(data: T): OkResponse<T> {
  return { data };
}

export function errorBody(err: AppError): ErrorResponse {
  const body: ErrorBody = { code: err.code, message: err.message };
  // remainingMeters solo viaja en OUTSIDE_GEOFENCE.
  if (err.code === 'OUTSIDE_GEOFENCE' && err.extra.remainingMeters !== undefined) {
    body.remainingMeters = err.extra.remainingMeters;
  }
  return { error: body };
}
