/** Shared projection of the live LLM registry into the browser model catalog. */

import type { Context } from '@deepseek-ai/cordis'
import type {
  ModelCatalog,
  ModelReasoning,
  ModelSelection,
} from './types.ts'

/** OpenRouter is the only provider whose free-only picker policy applies. */
const OPENROUTER_PROVIDER = 'openrouter'

/**
 * Build the browser model catalog without requiring a Session.
 * @param ctx - Host context carrying the live LLM registry.
 * @param defaultSelection - deployment default used before a Session selects a model.
 * @returns successful non-empty provider groups and isolated provider failures.
 */
export async function buildModelCatalog(
  ctx: Context,
  defaultSelection: ModelSelection = ctx.agentDefaultModel.currentSelection(),
): Promise<ModelCatalog> {
  const providers = ctx.llm.listProviders()
  const catalog = await Promise.all(providers.map(async (provider) => {
    try {
      const models = await ctx.llm.listModels(provider.id)
      const visibleModels = provider.id === OPENROUTER_PROVIDER
        ? models.filter(model => model.free === true)
        : models
      const entries = await Promise.all(visibleModels.map(async (model) => {
        const resolved = await ctx.llm.resolveModelInfo(provider.id, model.id)
        const reasoning: ModelReasoning | undefined = resolved.reasoning === undefined
          ? undefined
          : {
            efforts: resolved.reasoning.efforts.map(effort => ({
              id: effort.id,
              name: effort.name,
              ...(effort.description === undefined ? {} : { description: effort.description }),
            })),
            ...(resolved.reasoning.defaultEffort === undefined
              ? {}
              : { defaultEffort: resolved.reasoning.defaultEffort }),
          }
        return {
          id: model.id,
          name: model.name,
          ...(model.description === undefined ? {} : { description: model.description }),
          ...(reasoning === undefined ? {} : { reasoning }),
        }
      }))
      return {
        kind: 'group' as const,
        group: { id: provider.id, name: provider.name, models: entries },
      }
    } catch (error) {
      return {
        kind: 'failure' as const,
        failure: {
          id: provider.id,
          name: provider.name,
          message: error instanceof Error ? error.message : String(error),
        },
      }
    }
  }))
  const groups = catalog.flatMap(item => item.kind === 'group' ? [item.group] : [])
    .filter(group => group.models.length > 0)
  const openrouter = groups.find(group => group.id === OPENROUTER_PROVIDER)
  const openrouterFallback = openrouter?.models.at(0)?.id
  const defaultInCatalog = groups.some(group => group.id === defaultSelection.provider
    && group.models.some(model => model.id === defaultSelection.model))
  const effectiveDefault = defaultSelection.provider !== OPENROUTER_PROVIDER
    || defaultInCatalog
    || openrouterFallback === undefined
    ? defaultSelection
    : {
      provider: OPENROUTER_PROVIDER,
      model: openrouterFallback,
    }
  return {
    default: { ...effectiveDefault },
    routableProviders: providers.map(provider => provider.id),
    groups,
    failures: catalog.flatMap(item => item.kind === 'failure' ? [item.failure] : []),
  }
}
