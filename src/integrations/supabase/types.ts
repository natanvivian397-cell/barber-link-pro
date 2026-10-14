export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.18"
  }
  public: {
    Tables: {
      barbers: {
        Row: {
          active: boolean
          created_at: string
          id: string
          name: string
          photo_path: string | null
          sort_order: number
        }
        Insert: {
          active?: boolean
          created_at?: string
          id?: string
          name: string
          photo_path?: string | null
          sort_order?: number
        }
        Update: {
          active?: boolean
          created_at?: string
          id?: string
          name?: string
          photo_path?: string | null
          sort_order?: number
        }
        Relationships: []
      }
      bookings: {
        Row: {
          barber_id: string | null
          booking_date: string
          booking_time: string
          created_at: string
          customer_name: string
          customer_phone: string
          duration_min: number
          id: string
          notes: string | null
          price: number
          service_id: string | null
          service_name: string
          status: string
        }
        Insert: {
          barber_id?: string | null
          booking_date: string
          booking_time: string
          created_at?: string
          customer_name: string
          customer_phone: string
          duration_min?: number
          id?: string
          notes?: string | null
          price?: number
          service_id?: string | null
          service_name: string
          status?: string
        }
        Update: {
          barber_id?: string | null
          booking_date?: string
          booking_time?: string
          created_at?: string
          customer_name?: string
          customer_phone?: string
          duration_min?: number
          id?: string
          notes?: string | null
          price?: number
          service_id?: string | null
          service_name?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "bookings_barber_id_fkey"
            columns: ["barber_id"]
            isOneToOne: false
            referencedRelation: "barbers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bookings_service_id_fkey"
            columns: ["service_id"]
            isOneToOne: false
            referencedRelation: "services"
            referencedColumns: ["id"]
          },
        ]
      }
      schedule_settings: {
        Row: {
          afternoon_end: string
          afternoon_start: string
          created_at: string
          is_open: boolean
          morning_end: string
          morning_start: string
          slot_min: number
          updated_at: string
          weekday: number
        }
        Insert: {
          afternoon_end?: string
          afternoon_start?: string
          created_at?: string
          is_open?: boolean
          morning_end?: string
          morning_start?: string
          slot_min?: number
          updated_at?: string
          weekday: number
        }
        Update: {
          afternoon_end?: string
          afternoon_start?: string
          created_at?: string
          is_open?: boolean
          morning_end?: string
          morning_start?: string
          slot_min?: number
          updated_at?: string
          weekday?: number
        }
        Relationships: []
      }
      services: {
        Row: {
          active: boolean
          created_at: string
          description: string | null
          duration_min: number
          id: string
          name: string
          photo_path: string | null
          price: number
          sort_order: number
        }
        Insert: {
          active?: boolean
          created_at?: string
          description?: string | null
          duration_min?: number
          id?: string
          name: string
          photo_path?: string | null
          price: number
          sort_order?: number
        }
        Update: {
          active?: boolean
          created_at?: string
          description?: string | null
          duration_min?: number
          id?: string
          name?: string
          photo_path?: string | null
          price?: number
          sort_order?: number
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      cancel_my_booking: {
        Args: { _id: string; _name: string; _phone: string }
        Returns: boolean
      }
      find_my_bookings: {
        Args: { _name: string; _phone: string }
        Returns: {
          booking_date: string
          booking_time: string
          id: string
          service_name: string
        }[]
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
