import React from 'react';
import { Route } from 'react-router-dom';
import { PhoenixDashboard } from '../components/phoenix/PhoenixDashboard';
import { PhoenixSummoning } from '../components/phoenix/PhoenixSummoning';

export function PhoenixRoutes() {
    return (
        <>
            <Route path="/phoenix" element={<PhoenixDashboard />} />
            <Route path="/summon" element={<PhoenixSummoning />} />
        </>
    );
}
