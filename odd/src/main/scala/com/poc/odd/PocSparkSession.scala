package com.poc.odd

import org.apache.spark.sql.SparkSession

/** Plain SparkSession builder. No runtime metadata listener — ODD Platform's
  * Spark collector is thin compared to OMD/DataHub, so this POC pushes data-entities
  * and lineage edges via the ODD Platform REST API from scripts/seed-odd.sh.
  */
object PocSparkSession {
  def builder(jobName: String): SparkSession.Builder =
    SparkSession.builder().appName(jobName).master("local[*]")
}
