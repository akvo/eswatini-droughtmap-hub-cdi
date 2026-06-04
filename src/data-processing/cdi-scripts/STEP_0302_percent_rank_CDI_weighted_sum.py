# -*- coding: utf-8 -*-
import os
from datetime import date, timedelta
from libs.config_reader import ConfigParser
from libs.statistics_operations import StatisticOperations
import libs.netcdf_functions as netcdf
# import numpy as np

# Origin for the NetCDF "days since" time axis (matches the rest of the pipeline).
ORIGIN_DATE = date(1900, 1, 1)


class CompositeDroughtIndicatorRanking:
    """
    This is the core processing class for executing all CDI ranking operations
    """
    def __init__(self):
        self.__config = ConfigParser()
        self.__stats = StatisticOperations()
        self.__output_dir = self.__config.get('output_dir').replace("\\", '/')
        self.__region = self.__config.get('region_name')
        self.__bounds = self.__config.get('bounds')
        self.__input_file = os.path.join(self.__output_dir, "STEP_0301_CDI_weighted_sum_{}.nc".format(self.__region))
        self.__input_data_set = netcdf.open_dataset(self.__input_file)
        self.__latitudes = self.__config.get('latitudes')
        self.__longitudes = self.__config.get('longitudes')
        self.__times = self.__input_data_set.variables['time'][:]
        self.__number_of_months = len(self.__times)
        self.__missing = -9999.0
        # initialize the output file and prepare internal value lists #
        self.__initialize_ranking_file()

    def __initialize_ranking_file(self):
        self.__output_file = os.path.join(self.__output_dir, "STEP_0302_CDI_pct_rank_{}.nc".format(self.__region))
        output_data_set = None
        try:
            # create the output file #
            out_properties = {
                'latitudes': self.__latitudes,
                'longitudes': self.__longitudes,
                'times': self.__times,
                'time_units': 'days since 1900-01-01 00:00:00.0 UTC'
            }
            output_data_set = netcdf.initialize_dataset(self.__output_file, out_properties)

            # variables #
            lst_rank = output_data_set.createVariable('cdi_wt_sum_pr', 'float32', ('time', 'latitude', 'longitude'))
            lst_rank.units = '1'
            lst_rank.missing_value = self.__missing
            lst_rank.standard_name = "cdi_weighted_pct_rank"
            lst_rank.long_name = "percent ranked weighted sum CDI"
        except IOError as ioe:
            print(ioe)
        except Exception as ex:
            print(ex)
        finally:
            if output_data_set is not None:
                output_data_set.close()

    def __group_by_calendar_month(self):
        """
        Group time-step indices by their TRUE calendar month (1-12), derived from
        the NetCDF time value (days since 1900-01-01). This is robust to gaps in the
        series: the NDMC vegetation inputs are permanently missing some months, so
        the CDI series is not a contiguous monthly run. Positional (index + 12)
        arithmetic would compare the wrong months together — grouping by the real
        calendar month ranks each month only against the same month in other years.

        Returns:
            dict mapping calendar month (int) -> list of time indices
        """
        groups = {}
        for idx, t in enumerate(self.__times):
            month = (ORIGIN_DATE + timedelta(days=int(t))).month
            groups.setdefault(month, []).append(idx)
        return groups

    def rank_all_months(self):
        """
        Percent-rank the CDI weighted sum within each calendar month across all years
        present for that month, writing each ranked slice back to its time index.
        """
        output_data_set = None
        try:
            output_data_set = netcdf.open_dataset(self.__output_file, 'a')
            for month, indices in self.__group_by_calendar_month().items():
                # load every year's slice for this calendar month #
                data = [
                    netcdf.extract_data(self.__input_data_set, 'cdi_weighted_sum', i)
                    for i in indices
                ]
                # rank the slices against each other (0.0 - 1.0) #
                ranked_data = self.__stats.rank_parameter(data)
                # write each ranked slice back to its original time index #
                for k, i in enumerate(indices):
                    output_data_set.variables['cdi_wt_sum_pr'][i] = ranked_data[k]
        except IOError:
            raise
        except Exception:
            raise
        finally:
            if output_data_set is not None:
                output_data_set.close()


def main():
    """
    This is the main entry point for the program
    """
    # initialize a new CDI Ranking class #
    rankings = CompositeDroughtIndicatorRanking()
    # rank the CDI values within each calendar month across years #
    print("Ranking CDI weighted sum data...")
    rankings.rank_all_months()


if __name__ == '__main__':
    main()
