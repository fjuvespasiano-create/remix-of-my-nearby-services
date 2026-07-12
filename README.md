# AgenddaAqui

Marketplace hiperlocal e portal cívico para **Vespasiano** e **São José da Lapa (MG)**. Reúne empresas, empregos, eventos, transporte, serviços públicos, representantes políticos, promoções, blog editorial com IA, push notifications e um painel administrativo completo.

---

## Sumário

- [Stack](#stack)
- [Como rodar](#como-rodar)
- [Estrutura de pastas](#estrutura-de-pastas)
- [Roteamento](#roteamento)
- [Backend (Lovable Cloud / Supabase)](#backend-lovable-cloud--supabase)
- [Autenticação e papéis](#autenticação-e-papéis)
- [Módulos funcionais](#módulos-funcionais)
- [Notificações Push (Web Push VAPID)](#notificações-push-web-push-vapid)
- [Blog com IA e conteúdo diário](#blog-com-ia-e-conteúdo-diário)
- [Scrapers e cron jobs](#scrapers-e-cron-jobs)
- [Secrets e variáveis de ambiente](#secrets-e-variáveis-de-ambiente)
- [Deploy](#deploy)
- [Convenções de código](#convenções-de-código)

---

## Stack

| Camada | Tecnologia |
|---|---|
| Framework | **TanStack Start v1** (React 19 + Vite 7, SSR + server functions) |
| Runtime servidor | Cloudflare Worker (`nodejs_compat`) via Lovable |
| Estilos | Tailwind CSS v4 + shadcn/ui + tokens semânticos |
| Estado / cache | TanStack Query v5 |
| Formulários | react-hook-form + Zod |
| Banco / Auth / Storage | **Lovable Cloud** (Supabase Postgres + RLS) |
| IA | Lovable AI Gateway (Gemini 2.5 Flash / GPT-5) |
| Scraping | Firecrawl (via connector) |
| Push | Web Push VAPID + Service Worker (`public/sw.js`) |
| Cron | `pg_cron` + `pg_net` batendo em `src/routes/api/public/hooks/*` |
| Animação | Framer Motion |
| Ícones | lucide-react |

---

## Como rodar

```bash
bun install
bun dev            # http://localhost:8080
bun run build      # build de produção (SSR + client)
bun run lint
```

Secrets do backend são injetados automaticamente pelo Lovable Cloud — não há `.env` local para copiar. As chaves `VITE_SUPABASE_*` já vêm preenchidas em `.env` pela integração.

---

## Estrutura de pastas

```
src/
├─ routes/                    # File-based routing do TanStack Router
│  ├─ __root.tsx              # shell, providers, JSON-LD, onAuthStateChange
│  ├─ index.tsx               # landing
│  ├─ admin.*.tsx             # painel administrativo (30+ telas)
│  ├─ painel.*.tsx            # painel do lojista/usuário
│  ├─ empresa.$slug.tsx       # perfil público de empresa
│  ├─ blog.$slug.tsx          # post do blog
│  ├─ eventos.$slug.tsx       # detalhe de evento
│  ├─ empregos.$id.tsx        # detalhe de vaga
│  ├─ representantes.$id.tsx  # perfil do parlamentar
│  ├─ api/public/hooks/*.ts   # endpoints públicos chamados por pg_cron
│  ├─ api/public/push/*.ts    # tracking e resubscribe de push
│  └─ sitemap[.]xml.ts        # sitemap dinâmico
├─ components/
│  ├─ site/                   # Header, Footer, SiteLayout, ChatWidget, Onboarding…
│  ├─ panel/                  # ListingForm, HoursEditor, PremiumLock…
│  ├─ qa/                     # BugReportButton
│  └─ ui/                     # shadcn/ui gerado
├─ features/
│  ├─ jobs/                   # queries, tipos, cards de vagas
│  ├─ live-feed/              # widget de atividades ao vivo
│  └─ representatives/        # queries e helpers de parlamentares
├─ lib/
│  ├─ *.functions.ts          # server functions (createServerFn) chamáveis do cliente
│  ├─ *.server.ts             # helpers server-only (Firecrawl, dispatch push, HMAC…)
│  ├─ data/                   # helpers isomórficos (resolveCityIdBySlug…)
│  ├─ scraping/               # utilitários compartilhados de scraping
│  └─ …                       # push-client, pwa, plans, format, utils, siteContent
├─ integrations/
│  ├─ supabase/               # client browser, client.server (admin), auth-middleware
│  └─ lovable/                # broker OAuth (Google)
├─ hooks/                     # useCityId, useSelectedCity, useUnreadMessages…
└─ styles.css                 # design tokens + Tailwind v4

public/
├─ sw.js                      # Service Worker (push + cache)
├─ manifest.webmanifest       # PWA manifest
├─ robots.txt
└─ offline.html

supabase/
└─ config.toml                # apenas project_id — migrações vão via ferramenta

whatsapp-bot/                 # bot Node.js standalone (opcional, rodado à parte)
```

---

## Roteamento

Filenames com convenção **dot-separated**:

- `admin.push.$id.tsx` → `/admin/push/:id`
- `blog.$slug.tsx` → `/blog/:slug`
- `painel.notificacoes.preferencias.tsx` → `/painel/notificacoes/preferencias`
- `api/public/hooks/daily-blog-post.ts` → `POST /api/public/hooks/daily-blog-post`

`src/routeTree.gen.ts` é **auto-gerado** pelo plugin do Vite — não editar. Toda rota com `loader` define `errorComponent` e `notFoundComponent`.

---

## Backend (Lovable Cloud / Supabase)

### Padrão de acesso

| Cliente | Onde | Auth |
|---|---|---|
| `@/integrations/supabase/client` | componentes, hooks, realtime | sessão do usuário (RLS) |
| `requireSupabaseAuth` middleware | server functions autenticadas | bearer do usuário (RLS) |
| `@/integrations/supabase/client.server` (`supabaseAdmin`) | jobs privilegiados, webhooks, dispatch push | service role (**bypassa RLS**) |

Server functions vivem em `src/lib/*.functions.ts` e são chamadas do cliente via `useServerFn(fn)`. Helpers server-only ficam em `*.server.ts` e nunca são importados por componentes.

### Tabelas principais (64 no total)

Domínio comercial:
- `companies` (53 col.) — perfil, plano, badges, verificado, `plan_expires_at`
- `company_categories`, `company_media`, `company_faqs`, `company_projects`, `company_views`
- `categories`, `cities`, `plans_config`
- `leads`, `leads_planos`, `reviews`, `favorites`
- `promotions`, `coupons`, `banners`, `ad_campaigns` + `analytics_events`
- `listings`, `listing_categories`, `listing_messages`, `listing_reports`, `marketplace_items`

Conteúdo e cidade:
- `posts` + `post_categories` + `blog_categories` (unifica blog e notícias)
- `editorial_posts` (calendário editorial)
- `events` + `event_categories` + `event_sync_logs`
- `jobs` + `job_sources` + `job_sync_logs`
- `bus_lines` + `bus_sync_logs`, `tourist_attractions`, `emergency_contacts`, `public_services`
- `representatives` + `representative_activities` + `representative_attendance` + `representative_sync_logs`
- `procurements` (licitações), `shows`, `appointments`

Usuários e sistema:
- `profiles`, `user_roles` (enum `app_role`: admin / …), `notifications`
- `user_requests` (protocolo `SOL-000000`), `qa_tickets` + comentários/eventos
- `newsletter_subscribers`, `whatsapp_subscribers`
- `system_settings`, `media`, `live_feed_hidden`
- `push_subscriptions`, `push_notifications`, `push_deliveries`, `push_inbox`, `notification_templates`, `notification_preferences`

### Funções SQL relevantes

- `has_role(user_id, role)` — SECURITY DEFINER, base de toda policy admin
- `handle_new_user()` — cria `profiles` e notifica admins no signup
- `auto_grant_admin_for_seed_emails()` — promove e-mails-semente automaticamente
- `nearest_city(lat, lng)` — geolocalização
- `get_weekly_ranking()` — ranking Premium (score = visits×1 + leads×5 + reviews×8 + rating×4)
- `refresh_company_rating(company_id)` + trigger `trg_reviews_refresh_company`
- `enforce_premium_verified()` — força `is_verified=true` e badges em planos Premium
- `enforce_promotion_limit()` — Premium: 1 promoção; Free: bloqueado
- `notify_admins_new_user_request()` — dispara notificação in-app
- `track_ad_event(ad_id, kind)` — impressões/cliques
- `increment_push_counter(notification_id, counter)` — delivered/opened/clicked
- `admin_restore_table_tx(table, rows, mode)` — restore transacional com allowlist
- `qa_on_status_change()` — timeline + notificação ao autor

### Storage buckets (privados)

- `qa-attachments` — anexos de bug reports
- `promotion-images` — imagens de promoções
- `backups` — dumps do admin backup

---

## Autenticação e papéis

- **Provedores:** email/senha + Google OAuth (via broker `@/integrations/lovable`, iframe-safe)
- **Sessão:** persistida em `localStorage` pelo cliente Supabase
- **Papéis:** enum `app_role` em tabela separada `user_roles`. Nunca armazenar role em `profiles` — evita escalation.
- **Admins-semente:** `fjuvespasiano@gmail.com` e `williamiurd.ramos@gmail.com` recebem `admin` no primeiro login (trigger `auto_grant_admin_for_seed_emails`).
- **Gate de rotas:** `src/routes/_authenticated/route.tsx` (managed layout, `ssr: false`) protege `/painel/*` e `/admin/*`. Rotas admin adicionais verificam `has_role(uid, 'admin')`.
- **Bearer nas server functions:** anexado por `src/integrations/supabase/auth-attacher.ts` registrado em `src/start.ts`.

---

## Módulos funcionais

### Público (`src/routes/*`)
- **Landing** com hero, categorias, cidades, blog, ao vivo, representantes (widgets escondem quando vazios)
- **Busca** unificada (`/buscar`) + `SearchBar` com sugestões
- **Empresas** — listagem por cidade/categoria, perfil com avaliações, FAQ, projetos, media gallery, favoritos, reputação, cupons
- **Marketplace / Listings** — anúncios de particulares com mensagens e reports
- **Empregos** — free + premium, saved searches, filtros
- **Eventos, Shows, Turismo** (`/o-que-fazer`, `/roteiro-turistico`)
- **Transporte público** (`/transporte`, `/transporte/linhas`) — 14 linhas mapeadas SJL
- **Serviços públicos, Emergência, Transparência, Representantes** (feed, ranking, perfil)
- **Blog & notícias** unificado com categorias coloridas e toggle news/blog
- **Promoções, Contato, Sobre, Planos**

### Painel do usuário (`/painel/*`)
Empresas, anúncios (novo/editar), avaliações, favoritos, leads, mensagens, promoções, ranking (Premium), notificações (inbox + preferências), perfil.

### Painel administrativo (`/admin/*`)
30+ telas: empresas, empregos, eventos, blog, blog-AI, calendário editorial, cidades, categorias, planos, banners/anúncios, analytics de anúncios, promoções, cupons, leads, solicitações, duplicados, backup, emergência, turismo, serviços públicos, transporte, representantes, ao-vivo, QA/bug tracker, textos do site, push (histórico, novo, templates, detalhe), scrapers (SJL, Câmara SJL, Vespasiano).

---

## Notificações Push (Web Push VAPID)

- **Service Worker:** `public/sw.js` (fora do escopo do vite-plugin-pwa; handler `push` + `notificationclick`)
- **Subscribe:** `src/lib/push-client.ts` + `EnableNotifications.tsx`
- **Server:**
  - `push.functions.ts` — inbox, preferências, subscribe/unsubscribe
  - `push-send.server.ts` — assina JWT VAPID, envia via `fetch` para endpoint do browser
  - `push-dispatch.server.ts` — segmentação por categoria + horário silencioso
  - `admin-push.functions.ts` — criação, templates, envio manual/agendado
- **Tracking:** `/api/public/push/track.ts` — HMAC-assinado (`PUSH_TRACK_SECRET`) para incrementar `delivered_count` / `opened_count` / `clicked_count`
- **Resubscribe:** `/api/public/push/resubscribe.ts` — SW rota-tokens expirados

Cron `push-scheduler` roda a cada minuto e envia notificações agendadas.

---

## Blog com IA e conteúdo diário

- **`/admin/blog-ai`** — UI de geração manual: keywords + categoria (`empresa` / `cidade` / `digital`) + contexto opcional, gera markdown editável e salva em `posts`.
- **`daily-blog-post` endpoint** (`src/routes/api/public/hooks/daily-blog-post.ts`) — cron diária 08:00 BRT rotaciona entre `empresa` / `cidade` / `digital`, valida ≥2500 caracteres, dedup contra posts recentes, salva na tabela `posts`.
- **Modelo:** Gemini 2.5 Flash via Lovable AI Gateway (`LOVABLE_API_KEY`).

---

## Scrapers e cron jobs

Todos os endpoints ficam em `src/routes/api/public/hooks/` e exigem header `x-cron-secret` (ver `src/lib/cron-auth.server.ts`, aceita `CRON_HOOK_SECRET` ou `CRON_SECRET`).

| Endpoint | Frequência | Fonte |
|---|---|---|
| `daily-blog-post` | 1×/dia 08:00 | Lovable AI |
| `push-scheduler` | 1×/min | tabela `push_notifications` |
| `jobs-sync` | horário | agregadores + fontes locais |
| `scrape-events` | diário | Firecrawl |
| `scrape-procurements` | diário | Firecrawl (licitações) |
| `scrape-services` | semanal | Firecrawl |
| `sync-bus` | manual/semanal | `bus-scrape.server.ts` |
| `sync-representatives` | semanal | Firecrawl (Câmaras) |
| `sync-original` | on-demand | reimport genérico |
| `whatsapp-weekly-digest` | segunda 09:00 | `whatsapp_subscribers` |
| `whatsapp-opt-out` | on-demand | link do bot |

Agendamento via `pg_cron` + `pg_net.http_post`.

---

## Secrets e variáveis de ambiente

Já configurados no Lovable Cloud:

| Nome | Uso |
|---|---|
| `SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY` / `SUPABASE_SERVICE_ROLE_KEY` / `SUPABASE_DB_URL` | Backend Supabase |
| `LOVABLE_API_KEY` | AI Gateway |
| `FIRECRAWL_API_KEY` | Scrapers (managed connector) |
| `CRON_SECRET` / `CRON_HOOK_SECRET` | Autenticação dos endpoints `/api/public/hooks/*` |
| `PUSH_TRACK_SECRET` | HMAC dos tokens de tracking |
| `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` / `VAPID_SUBJECT` | Web Push (pendentes de configurar após remix) |

Client-side: `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, `VITE_SUPABASE_PROJECT_ID`.

**Regra:** `process.env.*` só dentro de `.handler()` de server function ou em `*.server.ts`. Nunca em módulos importados por componentes.

---

## Deploy

- **Lovable Cloud (recomendado):** botão **Publish** no topo. Frontend requer clicar "Update" para publicar; backend (server functions, cron, migrações) sobe imediatamente.
- **URL estável:** `project--<id>.lovable.app` (prod), `project--<id>-dev.lovable.app` (preview).
- Custom domain: Project Settings → Domains, após publicar.

---

## Convenções de código

- **TypeScript strict** — sem `any`, sem `ts-ignore`
- **Tokens semânticos apenas** — `bg-primary`, `text-foreground`, nunca `bg-blue-500`
- **`cn()` de `@/lib/utils`** para classes condicionais
- **Mobile-first** — grid começa em 1 coluna
- **Componentes ≤150 linhas** — extrair sub-componentes acima disso
- **Server function** para toda chamada com secret ou service role
- **RLS obrigatório** em toda tabela pública + `GRANT` explícito
- **TanStack Query** para todo data fetching (loader + `useSuspenseQuery` ou `useQuery`)
- **Error / NotFound boundaries** obrigatórios em rotas com loader
- **`routeTree.gen.ts` nunca editado à mão**

---

## Documentação de referência

- `AGENTS.md` — instruções para agentes de IA operando no repositório
- `src/routes/README.md` — mapa detalhado de rotas
- `whatsapp-bot/README.md` — bot standalone de digest semanal

---

Made with care for Vespasiano e São José da Lapa 💙
