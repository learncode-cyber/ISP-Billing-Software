<?php

namespace App\Services\Compliance;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;

/**
 * BtrcNewsIngestionService — hybrid ingestion (Blueprint Section 23).
 *
 * btrc.gov.bd exposes no official RSS/API (confirmed during blueprint
 * research), so this scheduled job fetches the BTRC news page, extracts
 * candidate items, and stages them in compliance.btrc_news_candidates.
 * A platform admin then reviews + publishes via the Super Admin console —
 * NOTHING auto-publishes to tenants. This balances freshness with
 * accuracy and guards against the scraper misfiring if BTRC changes
 * their page structure.
 *
 * Runs as a scheduled job on the `notifications` queue (low frequency,
 * e.g. hourly). Platform-level — not tenant-scoped.
 */
class BtrcNewsIngestionService
{
    private const BTRC_NEWS_URL = 'https://btrc.gov.bd/news';

    public function ingest(): int
    {
        $newCandidates = 0;

        try {
            $response = Http::timeout(20)->get(self::BTRC_NEWS_URL);
            if (! $response->ok()) {
                return 0;
            }

            // Parse the news listing HTML -> [ ['title'=>..., 'url'=>..., 'excerpt'=>...], ... ]
            // Actual DOM extraction is filled in during Phase 6 hardening
            // against the live page structure; kept as the integration
            // boundary here so the moderation pipeline is reviewable now.
            $items = $this->extractItems($response->body());

            foreach ($items as $item) {
                // source_url is UNIQUE -> insertOrIgnore dedupes automatically.
                $inserted = DB::table('compliance.btrc_news_candidates')->insertOrIgnore([
                    'id' => (string) \Illuminate\Support\Str::uuid(),
                    'title' => $item['title'],
                    'source_url' => $item['url'],
                    'raw_excerpt' => $item['excerpt'] ?? null,
                    'scraped_at' => now(),
                    'processed' => false,
                ]);
                $newCandidates += $inserted;
            }
        } catch (\Throwable $e) {
            \Illuminate\Support\Facades\Log::warning('BTRC news ingestion failed: '.$e->getMessage());
        }

        return $newCandidates;
    }

    private function extractItems(string $html): array
    {
        // HTML parsing (e.g. via Symfony DomCrawler) — integration boundary.
        return [];
    }
}
