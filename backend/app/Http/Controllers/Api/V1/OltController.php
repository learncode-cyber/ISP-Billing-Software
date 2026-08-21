<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Network\OltDevice;
use App\Services\OltService;
use Illuminate\Http\Request;

/**
 * Reproduces verified OLT "Add New Device" modal exactly: Device Type
 * (BDCOM/V-SOL/ZTE/Huawei/Fiberhome), Device IP, Login Username, Password,
 * SNMP Port (default 161), SNMP Community (default 'public'), "Check
 * Connection" button. Extends with the ONU/PON hierarchy the audit
 * flagged as [NOT VERIFIED post-registration] — see network.onu_devices.
 */
class OltController extends Controller
{
    public function __construct(private OltService $oltService)
    {
    }

    public function index()
    {
        return response()->json(OltDevice::with('ponPorts')->get());
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'device_name' => 'required|string|max:150',
            'device_type' => 'required|in:bdcom,v-sol,zte,huawei,fiberhome',
            'device_ip' => 'required|ip',
            'login_username' => 'required|string',
            'password' => 'required|string',
            'snmp_port' => 'nullable|integer',
            'snmp_community' => 'nullable|string',
            'telnet_port' => 'nullable|integer',
        ]);

        $device = OltDevice::create([
            'device_name' => $validated['device_name'],
            'device_type' => $validated['device_type'],
            'device_ip' => $validated['device_ip'],
            'login_username_encrypted' => encrypt($validated['login_username']),
            'password_encrypted' => encrypt($validated['password']),
            'snmp_port' => $validated['snmp_port'] ?? 161,
            'snmp_community_encrypted' => encrypt($validated['snmp_community'] ?? 'public'),
            'telnet_port' => $validated['telnet_port'] ?? null,
        ]);

        return response()->json($device, 201);
    }

    /** Preserves verified "Check Connection" button behavior exactly. */
    public function checkConnection(OltDevice $oltDevice)
    {
        $result = $this->oltService->checkConnection($oltDevice);

        $oltDevice->update([
            'connection_status' => $result['reachable'] ? 'connected' : 'unreachable',
            'last_checked_at' => now(),
        ]);

        return response()->json(['reachable' => $result['reachable'], 'message' => $result['message']]);
    }

    /** Triggers an SNMP discovery sweep to populate PON ports + ONUs. */
    public function discoverOnus(OltDevice $oltDevice)
    {
        $this->oltService->discoverOnusAsync($oltDevice->id);

        return response()->json(['status' => 'discovery_queued']);
    }
}
