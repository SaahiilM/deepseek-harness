/**
 * Adaptive chooser of the directory-picker seam: resolves the host's
 * situation once at boot (bind host, SSH launch, display session, Linux
 * chooser binary) and mounts the matching interaction — `native` or `browse`
 * — as real Loader entries in the in-memory root tree. Each interaction is a
 * pair: the Host backend serving the seam capability and the client surface
 * occupying ui-workspace's directory-flow holes. Both arrive as ordinary
 * entries, so the surface is discovered exactly as a config-row's would be
 * and one resolved choice still swaps both faces; pinning an interaction is
 * either composing that pair directly or setting this row's `pin` config
 * (the web app feeds it through `--directory-picker`).
 * @module @deepseek-ai/dsh-host-directory-picker-auto
 */

import type { Context } from '@deepseek-ai/cordis'
// Empty type imports carry the `loader` and `webServer` Context merges for the reads below.
import type {} from '@deepseek-ai/cordis-plugin-loader'
import type {} from '@deepseek-ai/dsh-host-webserver'
import { launchedThroughSsh, launchEnvironmentOf } from '@deepseek-ai/dsh-launch-environment'
import z from '@deepseek-ai/schemastery'
import { canExecute, hasLinuxChooserBinary } from './probe.ts'
import type { DirectoryPickerBackendKind } from './resolve.ts'
import { resolveDirectoryPickerBackend } from './resolve.ts'

export { canExecute, hasLinuxChooserBinary } from './probe.ts'
export type { DirectoryPickerBackendKind, DirectoryPickerEnv, DirectoryPickerHostFacts } from './resolve.ts'
export { resolveDirectoryPickerBackend } from './resolve.ts'

/** Cordis plugin name. */
export const name = 'directory-picker-auto'
/** Required services: the effective bind host (`webServer`) and the entry tree the backend mounts into (`loader`). */
export const inject = ['webServer', 'loader']

/** Optional composition config. */
export interface Config {
  /**
   * Pin the interaction instead of resolving it from host facts: `native`
   * mounts the OS-dialog pair, `browse` the in-app browser pair, and an
   * absent value keeps the boot-time resolution. A deployment serving
   * operator surfaces the boot facts cannot see — one server reached by both
   * a local browser and remote phones, for example — pins from its launch
   * flags; the web app feeds this field through `--directory-picker`.
   */
  pin?: DirectoryPickerBackendKind
}

/** Schemastery validation for {@link Config}. */
export const Config: z<Config> = z.object({
  pin: z.union(['native', 'browse']),
})

/**
 * Host backend package per resolved kind — fixed composition vocabulary, not a
 * tunable. Exported because the reference is a runtime string the static
 * config gate cannot see in a yml row: `verify-cordis-config` requires every
 * app composing this chooser to declare both values as dependencies.
 */
export const BACKEND_PACKAGES: Record<DirectoryPickerBackendKind, string> = {
  native: '@deepseek-ai/dsh-host-directory-picker-native',
  browse: '@deepseek-ai/dsh-host-directory-picker-browse',
}

/**
 * Client surface package per resolved kind, mounted with its backend so one
 * resolved interaction still composes both faces. Declared as dependencies by
 * every composing app for the same reason as {@link BACKEND_PACKAGES}. Only the
 * specifier is referenced here because the packages belong to the Client
 * program, so no import of them exists on this side.
 */
export const SURFACE_PACKAGES: Record<DirectoryPickerBackendKind, string> = {
  native: '@deepseek-ai/dsh-client-ui-directory-picker-native',
  browse: '@deepseek-ai/dsh-client-ui-directory-picker-browse',
}

/**
 * Mount the interaction named by the `pin` config, or resolve it from one
 * boot-time sample when unpinned; either way the chosen backend and surface
 * land as Loader entries and the effect's disposer removes both entries and
 * joins their fibers' teardown, so unloading this plugin returns only after
 * both faces of the mounted interaction (and their dependents) quiesced.
 * @param ctx - cordis context carrying the injected `webServer` and `loader`.
 * @param config - the row's validated {@link Config}.
 */
export async function apply(ctx: Context, config: Config): Promise<void> {
  const backend: DirectoryPickerBackendKind = config.pin ?? resolveDirectoryPickerBackend({
    bindHost: ctx.webServer.host,
    platform: process.platform,
    ssh: launchedThroughSsh(launchEnvironmentOf(ctx)),
    env: process.env,
    linuxChooser: hasLinuxChooserBinary(process.env.PATH, canExecute),
  })
  await ctx.effect(async () => {
    // Root-tree create: the Loader root is in-memory (write() is a no-op), so
    // the mounted rows can never be persisted back into a config file. The
    // backend lands first: the surface's browser half drives the capability
    // the backend registers.
    const ids: string[] = []
    const unmount = async () => {
      for (const id of [...ids].reverse()) {
        // Tree teardown (group.stop) can have removed the entry already;
        // nothing is left to unmount or await then.
        const entry = ctx.loader.store[id]
        if (entry === undefined) continue
        const disposal = entry.fiber?.dispose()
        ctx.loader.remove(id)
        await disposal
      }
    }
    try {
      for (const name of [BACKEND_PACKAGES[backend], SURFACE_PACKAGES[backend]]) {
        const id = await ctx.loader.create({ name })
        ids.push(id)
        const entry = ctx.loader.resolve(id)
        if (entry.fiber === undefined) throw new Error(`directory-picker-auto: failed to load ${name}`)
        await entry.fiber.await()
      }
    } catch (cause) {
      // Setup owns the entries it created until it returns the disposer: leaving
      // the backend mounted would make a retry collide with its own
      // directoryPicker registration.
      await unmount()
      throw cause
    }
    return unmount
  }, 'directory-picker-auto: interaction entries')
}
