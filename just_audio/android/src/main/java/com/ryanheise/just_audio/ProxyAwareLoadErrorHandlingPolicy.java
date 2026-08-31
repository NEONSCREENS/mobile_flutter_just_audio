package com.ryanheise.just_audio;

import androidx.media3.common.C;
import androidx.media3.datasource.HttpDataSource;
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy;
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy;

/**
 * Stops ExoPlayer repeating a decision a {@code StreamAudioSource} has already made.
 *
 * <p>The proxy that serves a {@code StreamAudioSource} answers every failure from
 * {@code request()} with HTTP 500, and it does so only after that source has finished its own
 * retrying. ExoPlayer cannot see any of that, so the default policy reloads the request three
 * more times and the source's whole ladder runs again from the top. Measured against a stub of
 * both hosts on SEI730 hardware: four times the requests for one decision, and about eleven
 * extra seconds before the app is told anything.
 *
 * <p>So a response code here means "already final, do not reload". Everything else keeps the
 * default behaviour — in particular a body that breaks part way through, which the proxy
 * swallows and the source therefore never sees. That one is worth reloading, and it is the only
 * error ExoPlayer is in a position to recover.
 */
public class ProxyAwareLoadErrorHandlingPolicy extends DefaultLoadErrorHandlingPolicy {

    @Override
    public long getRetryDelayMsFor(LoadErrorHandlingPolicy.LoadErrorInfo loadErrorInfo) {
        if (loadErrorInfo.exception instanceof HttpDataSource.InvalidResponseCodeException) {
            // C.TIME_UNSET is the contract for "do not retry": the caller turns it into
            // Loader.DONT_RETRY_FATAL and surfaces the error immediately.
            return C.TIME_UNSET;
        }

        return super.getRetryDelayMsFor(loadErrorInfo);
    }
}
