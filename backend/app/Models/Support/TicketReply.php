<?php

namespace App\Models\Support;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Model;

class TicketReply extends Model
{
    use BelongsToTenant;

    protected $table = 'support.ticket_replies';
    protected $keyType = 'string';
    public $incrementing = false;
    public $timestamps = false;

    protected $fillable = ['tenant_id', 'ticket_id', 'author_type', 'author_id', 'message'];
}
